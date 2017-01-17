module http.request;

import core.thread;
import core.time;

import std.algorithm;
import std.array;
import std.conv;
import std.concurrency;
import std.exception;
import std.range;
import std.string;
import std.uni : sicmp;

import http;

class HttpRequest : HttpInstance
{
private:
	Socket remote;
	bool persistent;

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
			auto connection = getHeader("Connection");

			// Fix for poor HTTP implementations.
			if (connection.empty)
			{
				connection = getHeader("Proxy-Connection");
			}

			switch (version_) with (HttpVersion)
			{
				default:
					auto r = new HttpResponse(socket, HttpStatus.httpVersionNotSupported);
					r.send();
					break;

				case v1_0:
					persistent = false;

					if (!connection.empty)
					{
						persistent = !sicmp(connection, "keep-alive");
					}
					break;

				case v1_1:
					if (host.empty)
					{
						badRequest(socket);
						return;
					}

					persistent = true;

					if (!connection.empty)
					{
						persistent = !!sicmp(connection, "close");
					}
					break;
			}

			switch (method) with (HttpMethod)
			{
				case none:
					badRequest(socket);
					return;

				case connect:
					handleConnect();
					break;

				case get:
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
					r.receive();
					r.send(socket);
					break;

				default:
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

		if (headers.length)
		{
			headers.byKeyValue.each!(x => result.writeln(x.key ~ ": " ~ x.value));
		}

		result.writeln();
		return result.data;
	}

	bool receive()
	{
		auto line = socket.readln(overflow);

		if (line.empty)
		{
			yield();
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

		for (char[] header; !(header = socket.readln(overflow)).empty;)
		{
			auto key = header.munch("^:");
			header.munch(": ");
			auto value = header;
			headers[key.idup] = value.idup;
		}

		auto length_str = getHeader("Content-Length");

		if (!length_str.empty)
		{
			body_ = socket.readlen(overflow, to!size_t(length_str));
		}

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

			if (Socket.select(reads, null, errors) <= 0)
			{
				persistent = false;
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

			Thread.yield();

			if (!count)
			{
				break;
			}

			scope (exit)
			{
				if (!persistent)
				{
					disconnect();
				}
			}
		}
	}
}
