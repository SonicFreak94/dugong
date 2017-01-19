module http.socket;

public import std.socket;

import core.time;

/// Convenience wrapper for TcpSocket
class HttpSocket : TcpSocket
{
public:
	this(lazy Duration timeout = 5.seconds)
	{
		super();
		super.blocking = false;

		setOption(SocketOptionLevel.SOCKET, SocketOption.SNDTIMEO, timeout);
		setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, timeout);
	}

	this(InternetAddress addr, lazy Duration timeout = 5.seconds)
	{
		super(addr);
		super.blocking = false;

		setOption(SocketOptionLevel.SOCKET, SocketOption.SNDTIMEO, timeout);
		setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, timeout);
	}

	this(in string address, ushort port, lazy Duration timeout = 5.seconds)
	{
		auto addr = new InternetAddress(address, port);
		this(addr, timeout);
	}
}
