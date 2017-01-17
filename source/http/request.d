module http.request;

import core.thread;
import core.time;

import std.array;
import std.conv;
import std.exception;
import std.string;

import http;

class HttpRequest : HttpInstance
{
private:
	Socket remote;

public:
	HttpMethod method;
	string requestUrl;

	this(Socket socket)
	{
		super(socket);
	}

	override void clear()
	{
		super.clear();
		method     = HttpMethod.none;
		requestUrl = null;
	}

	override void disconnect()
	{
		super.disconnect();
		enforce(socket is null);
		remote.disconnect();
		remote = null;
	}

	void run()
	{
		scope (exit)
		{
			disconnect();
		}

		while (connected())
		{
			if (remote !is null && remote.isAlive)
			{
				switch (method) with (HttpMethod)
				{
					case connect:
						connectProxy();
						continue;

					case get:
					case head:
						if (!receive())
						{
							continue;
						}
						break;

					default:
						throw new Exception("Unsupported method for persistent connections: " ~ method.toString());
				}
			}
			else if (!receive())
			{
				continue;
			}

			if (!connected())
			{
				break;
			}

			auto host = getHeader("Host");

			switch (method) with (HttpMethod)
			{
				case none:
					badRequest(socket);
					return;

				case connect:
					handleConnect();
					break;

				case get:
				case head:
					// Pull the host from the headers.
					// If none is present, try to use the request URL.
					auto i = host.lastIndexOf(":");

					// TODO: proper URL parsing
					string address;
					ushort port;

					if (i >= 0)
					{
						address = host[0 .. i];
						port = to!ushort(host[++i .. $]);
					}
					else
					{
						address = host;
						port = 80;
					}

					if (remote is null || !remote.isAlive)
					{
						remote = new TcpSocket(new InternetAddress(address, port));
					}

					send(remote);
					auto r = new HttpResponse(remote);
					// TODO: don't try to receive the body!
					r.receive();
					r.send(socket);

					if (!r.isPersistent)
					{
						r.disconnect();
					}
					break;

				default:
					debug import std.stdio;
					debug synchronized
					{
						stderr.write(method.toString());
						stderr.writeln();
					}
					break;
			}

			if (!persistent)
			{
				break;
			}
		}
	}

	void send(Socket s)
	{
		auto str = toString();
		s.send(cast(ubyte[])str ~ body_);
	}

	void send()
	{
		send(socket);
	}

	override string toString()
	{
		Appender!string result;

		result.writeln(method.toString(), ' ', requestUrl, ' ', version_.toString());

		auto headerString = super.toHeaderString();
		if (!headerString.empty)
		{
			result.writeln(headerString);
		}

		result.writeln();
		return result.data;
	}

	bool receive()
	{
		char[] line;

		if (!socket.readln(overflow, line) && line.empty)
		{
			import std.stdio;
			disconnect();
			return false;
		}

		if (line.empty)
		{
			return false;
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

		super.parseHeaders();
		return true;
	}

private:
	void handleConnect()
	{
		auto address = requestUrl.split(':');

		remote = new TcpSocket(new InternetAddress(address[0], to!ushort(address[1])));
		enforce(remote.isAlive, "Failed to connect to remote server: " ~ requestUrl);

		auto response = new HttpResponse(socket);
		response.send();

		connectProxy();
	}

	bool forward(Socket from, Socket to)
	{
		ubyte[1024] buffer;
		auto length = from.receive(buffer);

		if (!length || length == Socket.ERROR)
		{
			return length == Socket.ERROR;
		}

		to.send(buffer[0 .. length]);
		return true;
	}

	void connectProxy()
	{
		auto errors = new SocketSet();
		auto reads  = new SocketSet();

		while (socket.isAlive && remote.isAlive)
		{
			errors.add(remote);
			errors.add(socket);
			reads.add(remote);
			reads.add(socket);

			if (Socket.select(reads, null, errors, 5.seconds) <= 0)
			{
				disconnect();
				break;
			}

			if (errors.isSet(socket))
			{
				throw new Exception(socket.getErrorText());
			}

			if (errors.isSet(remote))
			{
				throw new Exception(remote.getErrorText());
			}

			int count;

			if (reads.isSet(remote) && forward(remote, socket))
			{
				++count;
			}

			if (reads.isSet(socket) && forward(socket, remote))
			{
				++count;
			}

			if (!count)
			{
				disconnect();
				break;
			}
		}
	}
}
