module http.request;

import core.thread;
import core.time;

import std.array;
import std.concurrency;
import std.conv;
import std.exception;
import std.string;

import http;

/// A request received from a client or for sending to a server.
class HttpRequest : HttpInstance
{
private:
	Socket remote;
	HttpResponse response;
	bool established;
	HttpMethod method;
	string requestUrl;

public:
	/// Constructs an instance of $(D HttpRequest) using
	/// the specified connected socket.
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
		closeRemote();
	}

	/// Performs request parsing and/or connection persistence.
	void run()
	{
		scope (exit)
		{
			disconnect();
		}

		while (connected)
		{
			if (established)
			{
				if (!handlePersistence())
				{
					continue;
				}
			}
			else if (!receive())
			{
				continue;
			}

			if (!connected)
			{
				break;
			}

			established = isPersistent;
			auto host = getHeader("Host");

			switch (method) with (HttpMethod)
			{
				case none:
					// just send a bad request and close the connection.
					socket.sendBadRequest();
					return;

				case connect:
					handleConnect();
					break;

					// TODO: POST
					// TODO: OPTIONS

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
						closeRemote();

						try
						{
							remote = new HttpSocket(address, port);
						}
						catch (Exception)
						{
							socket.sendNotFound();
							clear();
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
						closeRemote();
					}
					break;

				default:
					debug synchronized
					{
						import std.stdio : stderr;
						stderr.writeln(method.toString());
					}
					break;
			}

			if (!isPersistent)
			{
				break;
			}

			wait();
		}
	}

	override string toString() const
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

		if (socket.readln(overflow, line) < 1 && line.empty)
		{
			disconnect();
			return false;
		}

		if (line.empty)
		{
			wait();
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

		debug synchronized
		{
			import std.stdio : stderr;
			stderr.writeln(toString());
		}
		return true;
	}

private:
	bool handlePersistence()
	{
		scope (exit)
		{
			wait();
		}

		if (method == HttpMethod.connect)
		{
			if (checkRemote())
			{
				handleConnect();
				return false;
			}

			return true;
		}

		immutable currHost = getHeader("Host");
		clear();

		scope (exit)
		{
			immutable newHost = getHeader("Host");
			if (newHost != currHost)
			{
				closeRemote();
			}
		}

		if (!receive() || !socket.peek())
		{
			disconnect();
			return false;
		}

		if (!checkRemote())
		{
			closeRemote();
			return false;
		}

		return true;
	}

	void closeRemote()
	{
		if (response !is null)
		{
			response.disconnect();
			response = null;
		}

		if (remote !is null)
		{
			remote.disconnect();
			remote = null;
		}
	}
	bool checkRemote()
	{
		return remote !is null && remote.isAlive && remote.peek() != 0;
	}

	void handleConnect()
	{
		if (!checkRemote())
		{
			try
			{
				auto address = requestUrl.split(':');
				remote = new HttpSocket(address[0], to!ushort(address[1]));
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
				catch (Exception)
				{
					// ignored
				}

				return;
			}

			auto response = new HttpResponse(socket, false);
			response.send();
		}

		connectProxy();
	}

	auto forward(Socket from, Socket to)
	{
		if (from is null || !from.isAlive)
		{
			return 0;
		}

		if (to is null || !to.isAlive)
		{
			return -1;
		}

		ubyte[1024] buffer;

		ptrdiff_t result, length;

		length = from.receiveYield(buffer);
		result = length;

		if (length > 0)
		{
			to.sendYield(buffer[0 .. length]);
		}

		while (length == buffer.length)
		{
			length = from.receiveYield(buffer);

			if (length < 1)
			{
				break;
			}

			if (length > 0)
			{
				to.sendYield(buffer[0 .. length]);
				result += length;
			}
		}

		return result;
	}

	void connectProxy()
	{
		if (!socket.isAlive)
		{
			return;
		}

		if (!checkRemote())
		{
			closeRemote();
			return;
		}

		auto t = new Thread(
		{
			auto sch = new FiberScheduler();
			sch.spawn(
			{
				while (forward(remote, socket) > 0)
				{
					Thread.sleep(1.msecs);
				}

				closeRemote();
			});

			sch.start(
			{
				while (checkRemote())
				{
					if (!forward(socket, remote))
					{
						disconnect();
						break;
					}

					Thread.sleep(1.msecs);
				}
			});
		});

		t.start();

		while (t.isRunning)
		{
			wait();
		}
	}
}
