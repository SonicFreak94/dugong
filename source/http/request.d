module http.request;

import core.thread;
import core.time;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.range;
import std.string;
import std.uni : sicmp;

import http;

class HttpRequest : HttpInstance
{
private:
	Appender!(char[]) overflow;

public:
	HttpMethod method;
	string requestUrl;
	HttpVersion version_;
	string[string] headers;
	ubyte[] body_;

	this(Socket socket)
	{
		super(socket);
	}

	override void disconnect()
	{
		overflow.clear();
		super.disconnect();
	}

	override void clear()
	{
		method     = HttpMethod.none;
		requestUrl = null;
		version_   = HttpVersion.none;
		headers    = null;
		body_      = null;
		overflow.clear();
	}

	// performs case insensitive key lookup
	string getHeader(in string key)
	{
		auto ptr = key in headers;

		if (ptr !is null)
		{
			return *ptr;
		}

		auto search = headers.byPair.find!(x => !sicmp(key, x[0]));

		if (!search.empty)
		{
			return takeOne(search).front[1];
		}

		return null;
	}

	override void run()
	{
		scope (exit)
		{
			disconnect();
		}

		bool persist;

		while (connected())
		{
			receive();

			if (!connected())
			{
				break;
			}

			auto host = getHeader("Host");
			auto connection = getHeader("Connection");

			/*
			if (connection.empty)
			{
				connection = getHeader("Proxy-Connection");
			}
			*/

			switch (version_) with (HttpVersion)
			{
				default:
					auto r = new HttpResponse(socket, HttpStatus.httpVersionNotSupported);
					r.send();
					break;

				case v1_0:
					persist = false;

					if (!connection.empty)
					{
						persist = !sicmp(connection, "keep-alive");
					}
					break;

				case v1_1:
					if (host.empty)
					{
						badRequest(socket);
						return;
					}

					persist = true;

					if (!connection.empty)
					{
						persist = !!sicmp(connection, "close");
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

					auto remote = new TcpSocket(new InternetAddress(address, port));
					send(remote);

					auto r = new HttpResponse(remote);
					r.run();
					r.send(socket);
					break;

				default:
					break;
			}

			if (!persist)
			{
				break;
			}

			clear();
		}
	}

	void send(Socket s)
	{
		auto str = toString();
		s.send(cast(ubyte[])str ~ body_);
	}

	override void send()
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

private:
	void receive()
	{
		auto line = socket.readln(overflow);

		if (line.empty)
		{
			disconnect();
			return;
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

		if (length_str.empty)
		{
			return;
		}

		body_ = socket.readlen(overflow, to!size_t(length_str));
	}

	void handleConnect()
	{
		scope (exit)
		{
			disconnect();
		}

		auto address = requestUrl.split(':');
		auto remote = new TcpSocket(new InternetAddress(address[0], to!ushort(address[1])));
		enforce(remote.isAlive, "Failed to connect to remote server: " ~ requestUrl);

		auto response = new HttpResponse(socket);
		response.send();

		scope (exit)
		{
			remote.disconnect();
		}

		socket.blocking = false;
		remote.blocking = false;

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

		auto errors = new SocketSet();
		auto reads  = new SocketSet();

		while (socket.isAlive && remote.isAlive)
		{
			errors.add(remote);
			errors.add(socket);
			reads.add(remote);
			reads.add(socket);

			if (!Socket.select(reads, null, errors, 1.seconds))
			{
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
				break;
			}

			Thread.yield();
		}
	}
}
