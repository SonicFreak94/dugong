module http.instance;

public import std.socket;

import core.time;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.range;
import std.string;
import std.uni : sicmp;

import http.common;
import http.enums;
import http.response;

interface IHttpInstance
{
	bool connected();
	void disconnect();
	string getHeader(in string key);
	void run();
	bool receive();
	void send(Socket s);
	void send();
	void clear();
}

abstract class HttpInstance : IHttpInstance
{
protected:
	Socket socket;
	bool persistent;

	Appender!(char[]) overflow;
	HttpVersion version_;
	string[string] headers;
	ubyte[] body_;
	bool chunked;

public:
	this(Socket socket, lazy Duration timeout = 5.seconds)
	{
		enforce(socket !is null, "socket must not be null!");
		enforce(socket.isAlive, "socket must be connected!");

		this.socket = socket;
		this.socket.setOption(SocketOptionLevel.SOCKET, SocketOption.SNDTIMEO, timeout);
		this.socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, timeout);
		this.socket.blocking = true;
	}

	void disconnect()
	{
		socket.disconnect();
		socket = null;
		clear();
	}

	void clear()
	{
		overflow.clear();

		persistent = false;
		version_   = HttpVersion.v1_1;
		headers    = null;
		body_      = null;
		chunked    = false;
	}


final:
	@property bool isPersistent() { return persistent; }
	@property bool isChunked() { return chunked; }

	bool connected()
	{
		return socket !is null && socket.isAlive;
	}

	string getHeader(in string key)
	{
		import std.uni : sicmp;

		auto ptr = key in headers;
		if (ptr !is null)
		{
			return *ptr;
		}

		auto search = headers.byPair.find!(x => !sicmp(key, x[0]));

		if (!search.empty)
		{
			return takeOne(search).front[1];
		}

		return null;
	}

	void parseHeaders()
	{
		for (char[] header; socket.readln(overflow, header) && !header.empty;)
		{
			auto key = header.munch("^:");
			header.munch(": ");
			auto value = header;
			headers[key.idup] = value.idup;
		}

		auto connection = getHeader("Connection");
		if (connection.empty)
		{
			connection = getHeader("Proxy-Connection");
		}

		switch (version_) with (HttpVersion)
		{
			case v1_0:
				persistent = !sicmp(connection, "keep-alive");
				break;

			case v1_1:
				persistent = !!sicmp(connection, "close");
				break;

			default:
				auto r = new HttpResponse(socket, HttpStatus.httpVersionNotSupported);
				r.send();
				disconnect();
				return;
		}

		auto length = getHeader("Content-Length");
		if (!length.empty)
		{
			socket.readlen(overflow, body_, to!size_t(length));
		}

		chunked = !getHeader("Transfer-Encoding").empty;
	}

	string toHeaderString()
	{
		if (!headers.length)
		{
			return null;
		}

		return headers.byKeyValue.map!(x => x.key ~ ": " ~ x.value).join("\r\n");
	}
}
