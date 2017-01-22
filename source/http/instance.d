module http.instance;

public import std.socket;

import core.time;

import std.algorithm;
import std.array;
import std.concurrency;
import std.conv;
import std.exception;
import std.range;
import std.string;
import std.uni : sicmp;

import http.common;
import http.enums;
import http.response;

/// Interface for HTTP instances.
interface IHttpInstance
{
	/// Returns the connected state of this instance.
	@property bool connected();
	/// Disconnects this instance.
	void disconnect();
	/// Main parsing routine.
	void run();
	/// Main receiving function.
	/// Returns: $(D true) if data has been received.
	bool receive();
	/// Sends the data stored in this instance to the given socket.
	void send(Socket s);
	/// Sends the data in this instance to its connected socket.
	void send();
	/// Clears the data in this instance.
	void clear();
}

/// Base class for $(D HttpRequest) and $(D HttpResponse).
abstract class HttpInstance : IHttpInstance
{
private:
	bool persistent;
	bool hasBody_;
	bool chunked;

protected:
	Socket socket;

	Appender!(char[]) overflow;
	HttpVersion version_;
	string[string] headers;
	ubyte[] body_;

public:
	this(Socket socket, bool hasBody = true, int keepAlive = 5, lazy Duration timeout = 15.seconds)
	{
		enforce(socket !is null, "socket must not be null!");
		enforce(socket.isAlive, "socket must be connected!");

		this.socket = socket;
		this.hasBody_ = hasBody;
		this.socket.blocking = false;
		this.socket.setTimeouts(keepAlive, timeout);
	}

	void disconnect()
	{
		socket.disconnect();
		socket = null;
	}

	void clear()
	{
		overflow.clear();

		persistent = false;
		version_   = HttpVersion.v1_1;
		headers    = null;
		body_      = null;
		chunked    = false;
	}

	void send(Socket s)
	{
		// This toString() is implemented by the inheriting class.
		s.sendYield(toString());

		if (!body_.empty)
		{
			s.sendYield(body_);
			return;
		}

		// TODO: multi-part
		// TODO: connection abort

		if (isChunked)
		{
			foreach (chunk; byChunk())
			{
				if (s.sendYield(chunk) < 1)
				{
					break;
				}
			}
		}
		else if (hasBody)
		{
			foreach (block; byBlock())
			{
				if (s.sendYield(block) < 1)
				{
					break;
				}
			}
		}
	}

	void send()
	{
		send(socket);
	}

final:
	/// Indicates whether or not this instance uses connection persistence.
	@property bool isPersistent() { return persistent; }
	/// Indicates whether or not this instance expects to have a body.
	@property bool hasBody() { return chunked || hasBody_; }
	/// Indicates whether or not the Transfer-Encoding header is present in this instance.
	@property bool isChunked() { return chunked; }
	/// Indicates whether or not ths instance is connected.
	@property bool connected() { return socket !is null && socket.isAlive; }

	string getHeader(in string key, string* realKey = null)
	{
		import std.uni : sicmp;

		auto ptr = key in headers;
		if (ptr !is null)
		{
			return *ptr;
		}

		auto search = headers.byPair.find!(x => !sicmp(key, x[0]));

		if (!search.empty)
		{
			auto result = takeOne(search);

			if (realKey !is null)
			{
				*realKey = result.front[0];
			}

			return result.front[1];
		}

		return null;
	}

	/// Reads available headers from the socket and populates
	/// $(D headers), performs error handling, maybe more idk.
	void parseHeaders()
	{
		foreach (char[] header; socket.byLine(overflow))
		{
			if (header.empty)
			{
				break;
			}

			auto key = header.munch("^:").idup;
			header.munch(": ");

			// If more than one Content-Length header is
			// specified, take the smaller of the two.
			if (!sicmp(key, "Content-Length"))
			{
				try
				{
					immutable length = getHeader(key);
					if (!length.empty)
					{
						const existing = to!size_t(length);
						const received = to!size_t(header);

						if (existing < received)
						{
							continue;
						}
					}
				}
				catch (Exception)
				{
					// ignored
				}
			}

			headers[key] = header.idup;
		}

		string key;
		immutable contentLength = getHeader("Content-Length", &key);
		chunked = !getHeader("Transfer-Encoding").empty;

		if (!contentLength.empty && chunked)
		{
			enforce(headers.remove(key));
		}
		else if (hasBody_)
		{
			hasBody_ = !contentLength.empty;
		}

		auto connection = getHeader("Connection");
		if (connection.empty)
		{
			connection = getHeader("Proxy-Connection");
		}

		switch (version_) with (HttpVersion)
		{
			case v1_0:
				persistent = !sicmp(connection, "keep-alive");
				break;

			case v1_1:
				persistent = !!sicmp(connection, "close");
				break;

			default:
				if (socket.isAlive)
				{
					socket.sendResponse(HttpStatus.httpVersionNotSupported);
				}

				disconnect();
				return;
		}
	}

	/// Converts the key-value pairs in $(D headers) to a string.
	string toHeaderString() const
	{
		if (!headers.length)
		{
			return null;
		}

		return headers.byKeyValue.map!(x => x.key ~ ": " ~ x.value).join("\r\n");
	}

	/// Read data from this instance by chunk (Transfer-Encoding).
	auto byChunk()
	{
		enforce(isChunked, "byChunk() called on instance with no chunked data.");

		return new Generator!(ubyte[])(
		{
			// readChunk yields the buffer whenever possible
			if (!socket.readChunk(overflow, body_))
			{
				disconnect();
			}
		});
	}

	/// Read data from this instance by block (requires Content-Length).
	auto byBlock()
	{
		immutable header = getHeader("Content-Length");
		enforce(!header.empty, "byBlock() called on instance with no Content-Length header.");

		const length = to!size_t(header);
		return socket.byBlock(overflow, length);
	}
}
