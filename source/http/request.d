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
	HttpVersion version_;
	string[string] headers;
	ubyte[] body_;

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
		version_ = _httpVersion.toVersion();

		enforce(version_ != HttpVersion.none, "Invalid HTTP version: " ~ _httpVersion);

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

		// TODO: body?
	}

	void run()
	{
		try
		{
			parse();
		}
		catch (Exception ex)
		{
			disconnect();
			return;
		}

		auto _ptr = "Host" in headers;
		string host = ptr is null ? null : *_ptr;
		bool persist;

		switch (version_) with (HttpVersion)
		{
			default:
				// TODO: 400 (Bad Request)
				break;

			case v1_0:
				persist = false;
				// TODO: check if persistent connection is enabled (non-standard for 1.0)
				break;

			case v1_1:
				persist = true;
				// TODO: check if persistent connection is *disabled* (default enabled)
				if (host.empty)
				{
					// TODO: 400 (Bad Request)
					disconnect();
				}
				break;
		}

		switch (method) with (HttpMethod)
		{
			case none:
				// TODO: 400 (Bad Request)?
				disconnect();
				break;

			case connect:
				// TODO: connect proxy
				// TODO: socket pool
				break;

			default:
				// TODO: passthrough (and caching obviously)
				// TODO: check for multipart
				break;
		}
	}

	override string toString()
	{
		// TODO
		throw new Exception("Not implemented");
	}
}
