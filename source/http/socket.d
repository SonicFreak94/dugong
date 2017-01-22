module http.socket;

public import std.socket;

import core.time;
import http.common : setTimeouts;

/// Convenience wrapper for TcpSocket
class HttpSocket : TcpSocket
{
public:
	this(int keepAlive = 5, lazy Duration timeout = 15.seconds)
	{
		super();
		super.blocking = false;
		this.setTimeouts(keepAlive, timeout);
	}

	this(InternetAddress addr, int keepAlive = 5, lazy Duration timeout = 15.seconds)
	{
		super(addr);
		super.blocking = false;
		this.setTimeouts(keepAlive, timeout);
	}

	this(in string address, ushort port, int keepAlive = 5, lazy Duration timeout = 15.seconds)
	{
		auto addr = new InternetAddress(address, port);
		this(addr, keepAlive, timeout);
	}
}
