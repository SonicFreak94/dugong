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
	HttpResponse response;
	bool established;

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
		closeRemote();
	}

	bool handleConnection()
	{
		if (method == HttpMethod.connect)
		{
			handleConnect();
			return false;
		}

		clear();

		if (!receive() || !checkRemote())
		{
			return false;
		}

		return true;
	}

	void run()
	{
		scope (exit)
		{
			disconnect();
		}

		while (connected())
		{
			if (established)
			{
				if (!handleConnection())
				{
					continue;
				}
			}
			else if (!receive())
			{
				// TODO: when concurrency happens, yield
				Thread.sleep(1.msecs);
				continue;
			}

			if (!connected())
			{
				break;
			}

			established = isPersistent;
			auto host = getHeader("Host");

			switch (method) with (HttpMethod)
			{
				case none:
					socket.sendBadRequest();
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

					if (!checkRemote())
					{
						try
						{
							remote = new TcpSocket(new InternetAddress(address, port));
						}
						catch (Throwable)
						{
							clear();
							socket.sendNotFound();
							closeRemote();
							break;
						}
					}

					send(remote);

					response = new HttpResponse(remote, method != head);
					response.receive();
					response.send(socket);

					if (checkRemote() && !response.isPersistent)
					{
						response.disconnect();
					}
					break;

				default:
					debug import std.stdio;
					debug synchronized
					{
						stderr.writeln(method.toString());
					}
					break;
			}

			if (!isPersistent)
			{
				break;
			}
		}
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

		debug import std.stdio;
		debug synchronized stderr.writeln(toString());
		return true;
	}

private:
	void closeRemote()
	{
		if (response !is null)
		{
			response.disconnect();
			response = null;
		}

		remote.disconnect();
		remote = null;
	}

	bool checkRemote()
	{
		if (remote is null)
		{
			return false;
		}

		if (!remote.isAlive)
		{
			closeRemote();
			return false;
		}

		return true;
	}

	void handleConnect()
	{
		if (!checkRemote())
		{
			try
			{
				auto address = requestUrl.split(':');
				auto remoteAddr = new InternetAddress(address[0], to!ushort(address[1]));
				remote = new TcpSocket(remoteAddr);
				enforce(remote.isAlive, "Failed to connect to remote server: " ~ requestUrl);
			}
			catch (Exception ex)
			{
				try
				{
					clear();
					socket.sendNotFound();
					closeRemote();
				}
				catch (Throwable)
				{
					// ignored
				}

				return;
			}

			auto response = new HttpResponse(socket);
			response.send();
		}

		connectProxy();
	}

	bool forward(Socket from, Socket to)
	{
		ubyte[1024] buffer;
		auto length = from.receive(buffer);

		if (!length)
		{
			from.disconnect();
			return false;
		}

		if (length == Socket.ERROR)
		{
			return true;
		}

		to.send(buffer[0 .. length]);
		return true;
	}

	void connectProxy()
	{
		auto errors = new SocketSet();
		auto reads  = new SocketSet();

		while (socket.isAlive && checkRemote())
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
			else if (errors.isSet(remote))
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
				closeRemote();
				break;
			}
		}
	}
}
