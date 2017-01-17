module http.instance;

public import std.socket;

import core.time;

import std.algorithm;
import std.array;
import std.exception;
import std.range;

import http.common;
import http.enums;

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
	Appender!(char[]) overflow;
	HttpVersion version_;
	string[string] headers;
	ubyte[] body_;

public:
	this(Socket socket, lazy Duration timeout = 15.seconds)
	{
		enforce(socket.isAlive, "socket must be connected!");

		this.socket = socket;
		this.socket.setOption(SocketOptionLevel.SOCKET, SocketOption.SNDTIMEO, timeout);
		this.socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, timeout);
		this.socket.blocking = true;
	}

	final bool connected()
	{
		return socket.isAlive();
	}

	void disconnect()
	{
		socket.disconnect();
		clear();
	}

	final string getHeader(in string key)
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

	void clear()
	{
		overflow.clear();
		version_ = HttpVersion.v1_1;
		headers  = null;
		body_    = null;
	}
}
