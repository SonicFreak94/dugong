module http.response;

import core.time;
import std.exception;

import http.common;
import http.enums;

// TODO: cookies?

class HttpResponse
{
private:
	Socket socket;

public:
	string[string] headers;
	HttpVersion httpVersion;
	int statusCode;

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
		socket.disconnect();
	}

	bool run()
	{
		return false;
	}
}
