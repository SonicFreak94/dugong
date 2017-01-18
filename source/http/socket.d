module http.socket;

public import std.socket;

class HttpSocket : TcpSocket
{
public:
	this()
	{
		super();
		super.blocking = false;
	}

	this(InternetAddress addr)
	{
		super(addr);
		super.blocking = false;
	}

	this(in string address, ushort port)
	{
		auto addr = new InternetAddress(address, port);
		this(addr);
	}
}
