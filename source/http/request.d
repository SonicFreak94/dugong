module http.request;

import core.time;
import std.array;
import std.exception;
import std.string;

import http.common;
import http.enums;

class HttpRequest
{
private:
	Socket socket;
	Appender!(char[]) overflow;

public:
	HttpMethod method;
	string requestUrl;
	HttpVersion httpVersion;
	string[string] headers;

	@property auto connected() const
	{
		return socket.isAlive;
	}

	this(Socket socket)
	{
		enforce(socket.isAlive);
		this.socket = socket;
		this.socket.setOption(SocketOptionLevel.SOCKET, SocketOption.SNDTIMEO, 15.seconds);
		this.socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, 15.seconds);
	}

	void disconnect()
	{
		overflow.clear();
		socket.disconnect();
	}

	void parse()
	{
		auto line = socket.readln(overflow);

		if (line.empty)
		{
			disconnect();
			return;
		}

		auto elements = line.split();
		enforce(elements.length > 1, "Too few parameters for request!");

		method = elements[0].toMethod();
		enforce(method != method.none, "Invalid method: " ~ elements[0]);

		auto _httpVersion = elements[$ - 1];
		httpVersion = _httpVersion.toVersion();

		enforce(httpVersion != HttpVersion.none, "Invalid HTTP version: " ~ _httpVersion);

		if (elements.length > 2)
		{
			requestUrl = elements[1].idup;
		}

		for (char[] header; !(header = socket.readln(overflow)).empty;)
		{
			auto key = header.munch("^:");
			header.munch(": ");
			auto value = header;
			headers[key.idup] = value.idup;
		}

		// TODO: body
	}

	bool run()
	{
		try
		{
			parse();
		}
		catch (Exception ex)
		{
			disconnect();
			return false;
		}

		if (httpVersion == HttpVersion.v1_1)
		{
			// TODO: send 400 (Bad Request), not enforce
			enforce(("Host" in headers) !is null, "Missing required host header for HTTP/1.1");
		}

		// TODO
		return false;
	}
}
