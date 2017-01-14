module http.request;

import core.time;
import std.array;
import std.conv;
import std.exception;
import std.string;
import std.stdio;

import http;

class HttpRequest : HttpInstance
{
private:
	Appender!(char[]) overflow;

public:
	HttpMethod method;
	string requestUrl;
	HttpVersion version_;
	string[string] headers;
	ubyte[] body_;

	this(Socket socket)
	{
		super(socket);
	}

	override void disconnect()
	{
		overflow.clear();
		super.disconnect();
	}

	override void run()
	{
		try
		{
			parse();
		}
		catch (Exception ex)
		{
			synchronized stderr.writeln(ex.msg);
			disconnect();
			return;
		}

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
				if ("Host" !in headers)
				{
					// TODO: 400 (Bad Request)
					disconnect();
					return;
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
				handleConnect();
				break;

			default:
				// TODO: passthrough (and caching obviously)
				// TODO: check for multipart
				break;
		}
	}

	override void send()
	{
		throw new Exception("Not implemented");
	}

private:
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

	void handleConnect()
	{
		Socket remote;

		try
		{
			auto address = requestUrl.split(':');
			remote = new TcpSocket(new InternetAddress(address[0], to!ushort(address[1])));
			enforce(remote.isAlive, "Failed to connect to remote server: " ~ requestUrl);

			auto response = new HttpResponse(socket);
			response.send();
		}
		catch (Exception ex)
		{
			synchronized stderr.writeln(ex.msg);
			disconnect();
			return;
		}

		scope (exit)
		{
			disconnect();
			remote.disconnect();
		}

		// HACK: all of this is so broken
		socket.blocking = true;
		socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, 1.seconds);
		//socket.setOption(SocketOptionLevel.SOCKET, SocketOption.SNDTIMEO, 1.seconds);

		remote.blocking = true;
		remote.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, 1.seconds);
		//remote.setOption(SocketOptionLevel.SOCKET, SocketOption.SNDTIMEO, 1.seconds);

		bool forward(Socket from, Socket to)
		{
			ubyte[1024] buffer;
			auto length = from.receive(buffer);

			if (length == Socket.ERROR)
			{
				return false;
			}

			if (!length)
			{
				return false;
			}

			to.send(buffer[0 .. length]);
			return true;
		}

		while (socket.isAlive && remote.isAlive)
		{
			int count;

			if (forward(remote, socket))
			{
				++count;
			}

			if (forward(socket, remote))
			{
				++count;
			}

			if (!count)
			{
				break;
			}
		}
	}
}
