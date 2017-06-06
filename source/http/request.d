module http.request;

import core.thread;
import core.time;

import std.array;
import std.concurrency;
import std.conv;
import std.exception;
import std.string;

import http;
import buffer;

/// A request received from a client or for sending to a server.
class HttpRequest : HttpInstance
{
private:
	HttpSocket remote;
	HttpResponse response;
	bool established;
	HttpMethod method;
	string requestUrl;

	alias BufferT = Buffer!(ubyte, 256 * 1024);
	BufferT _fwd_buffer;
	ubyte[1] _fwd_peek;

public:
	/// Constructs an instance of $(D HttpRequest) using
	/// the specified connected socket.
	this(HttpSocket socket)
	{
		super(socket);
	}

	override nothrow void clear()
	{
		super.clear();

		if (_fwd_buffer !is null)
		{
			_fwd_buffer.clear();
			_fwd_buffer = null;
		}

		method = HttpMethod.none;
		requestUrl = null;
	}

	override nothrow void disconnect()
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
			yield();

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

			switch (method) with (HttpMethod)
			{
				case none:
					// just send a bad request and close the connection.
					socket.sendBadRequest();
					disconnect();
					continue;

				case connect:
					handleConnect();
					break;

				case options:
				case get:
				case head:
				case post:
					if (!connectRemote())
					{
						break;
					}

					send(remote);

					response = new HttpResponse(remote, method == get);
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

		if (socket.readln(line) < 1 && line.empty)
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
		if (method == HttpMethod.connect)
		{
			if (!socket.peek(_fwd_peek))
			{
				debug synchronized
				{
					import std.stdio : stderr;
					stderr.writeln("Client connection closed.");
				}

				disconnect();
				return false;
			}

			if (checkRemote())
			{
				handleConnect();
				return false;
			}

			return true;
		}

		if (!socket.peek(_fwd_peek))
		{
			disconnect();
			return false;
		}

		immutable currHost = getHeader("Host");
		clear();

		if (!receive())
		{
			debug synchronized
			{
				import std.stdio : stderr;
				stderr.writeln("Client connection closed.");
			}

			disconnect();
			return false;
		}

		immutable newHost = getHeader("Host");
		if (newHost != currHost || !checkRemote())
		{
			closeRemote();
		}

		return true;
	}

	void handleConnect()
	{
		if (!checkRemote())
		{
			if (_fwd_buffer is null)
			{
				_fwd_buffer = new BufferT();
			}

			try
			{
				auto address = requestUrl.split(':');
				remote = new HttpSocket(address[0], to!ushort(address[1]));
				enforce(remote.isAlive, "Failed to connect to remote server: " ~ requestUrl);
			}
			catch (Exception ex)
			{
				clear();
				socket.sendNotFound();
				closeRemote();
				return;
			}

			auto response = new HttpResponse(socket, false);
			response.send();
		}

		connectProxy();
	}

	auto forward(scope HttpSocket from, scope HttpSocket to)
	{
		if (from is null || !from.isAlive)
		{
			return 0;
		}

		if (to is null || !to.isAlive)
		{
			return -1;
		}

		ptrdiff_t result, length;

		length = from.receiveYield(_fwd_buffer[]);
		result = length;

		if (length > 0)
		{
			to.sendYield(_fwd_buffer[0 .. length]);
			_fwd_buffer.addLength(length);
		}

		while (length == _fwd_buffer.length)
		{
			length = from.receiveYield(_fwd_buffer[]);

			if (length < 1)
			{
				break;
			}

			if (length > 0)
			{
				to.sendYield(_fwd_buffer[0 .. length]);
				_fwd_buffer.addLength(length);

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

		auto length = remote.peek(_fwd_peek);
		if (!length)
		{
			closeRemote();
			return;
		}
		else if (length > 0)
		{
			forward(remote, socket);
		}
		else
		{
			yield();
		}

		length = socket.peek(_fwd_peek);
		if (!length)
		{
			disconnect();
			return;
		}
		else if (length > 0)
		{
			forward(socket, remote);
		}
		else
		{
			yield();
		}
	}

	nothrow void closeRemote()
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
		return remote !is null && remote.isAlive && remote.peek(_fwd_peek) != 0;
	}

	bool connectRemote()
	{
		if (checkRemote())
		{
			return true;
		}

		// Pull the host from the headers.
		// If none is present, try to use the request URL.
		immutable host = getHeader("Host");
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

		closeRemote();

		try
		{
			remote = new HttpSocket(address, port);
			return true;
		}
		catch (Exception)
		{
			socket.sendNotFound();
			clear();
			closeRemote();
			return false;
		}
	}
}
