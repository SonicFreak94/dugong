module http.request;

import core.thread;
import core.time;

import std.array;
import std.concurrency;
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

	bool handlePersistence()
	{
		scope (exit)
		{
			yield();
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
							remote = new HttpSocket(address, port);
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
						closeRemote();
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

			yield();
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
			disconnect();
			return false;
		}

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

		if (remote !is null)
		{
			remote.disconnect();
			remote = null;
		}

		yield();
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
			return wouldHaveBlocked();
		}

		to.send(buffer[0 .. length]);
		return true;
	}

	void connectProxy()
	{
		while (socket.isAlive && checkRemote())
		{
			int count;

			if (forward(remote, socket))
			{
				++count;
			}
			else
			{
				closeRemote();
				yield();
				break;
			}

			yield();

			if (forward(socket, remote))
			{
				++count;
			}

			yield();

			if (!count)
			{
				closeRemote();
				break;
			}

			yield();
		}
	}
}
