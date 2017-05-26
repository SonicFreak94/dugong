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
	@safe @property bool connected() const;
	/// Disconnects this instance.
	nothrow void disconnect();
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
	nothrow void clear();
}

/// Base class for $(D HttpRequest) and $(D HttpResponse).
abstract class HttpInstance : IHttpInstance
{
private:
	bool persistent;
	bool hasBody_;
	bool chunked;
	bool isMultiPart_;
	string multiPartBoundary_;

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

	nothrow void disconnect()
	{
		socket.disconnect();
		socket = null;
	}

	nothrow void clear()
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
		// This toString() is implemented by the derived class.
		s.sendYield(toString());

		if (!body_.empty)
		{
			s.sendYield(body_);
			return;
		}

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

			return;
		}

		if (isMultiPart)
		{
			sendMultiPart(s);
		}
		else
		{
			if (!hasBody)
			{
				return;
			}

			foreach (block; byBlock())
			{
				if (s.sendYield(block) < 1)
				{
					break;
				}
			}
		}
	}

	final void sendMultiPart(Socket s)
	{
		immutable start = "--" ~ multiPartBoundary;
		immutable end = start ~ "--";

		while (true)
		{
			char[] _boundary;

			if (socket.readln(overflow, _boundary) < 1)
			{
				break;
			}

			enforce(_boundary.startsWith(start), "Malformed multipart line: boundary not found");
			s.writeln(_boundary);

			if (_boundary == end)
			{
				break;
			}

			string[string] _headers;

			foreach (line; socket.byLine(overflow))
			{
				s.writeln(line);

				if (line.empty)
				{
					break;
				}

				auto key = line.munch("^:").idup;
				line.munch(": ");
				_headers[key] = line.idup;
			}

			foreach (ubyte[] buffer; socket.byBlockUntil(start, overflow, true))
			{
				s.sendYield(buffer);
			}
		}
	}

	void send()
	{
		send(socket);
	}

final:
	@safe @property
	{
		/// Indicates whether or not this instance uses connection persistence.
		nothrow bool isPersistent() const { return persistent; }
		/// Indicates whether or not this instance expects to have a body.
		nothrow bool hasBody() const { return chunked || hasBody_; }
		/// Indicates whether or not the Transfer-Encoding header is present in this instance.
		nothrow bool isChunked() const { return chunked; }
		/// Indicates whether or not this instance contains multi-part data.
		nothrow bool isMultiPart() const { return isMultiPart_; }
		/// Gets the multi-part boundary for this instance.
		nothrow auto multiPartBoundary() const { return multiPartBoundary_; }
		/// Indicates whether or not ths instance is connected.
		bool connected() const { return socket !is null && socket.isAlive; }
	}

	@nogc nothrow string getHeader(in string key, string* realKey = null)
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

		// Duplicating because we will be modifying this string.
		auto contentType = getHeader("Content-Type").idup;

		if (!contentType.empty && contentType.toLower().canFind("multipart"))
		{
			contentType.munch(" ");
			contentType.munch("^ ");
			contentType.munch(" ");

			immutable boundaryParam = contentType.munch("^=");
			contentType.munch(" =");

			if (!boundaryParam.sicmp("boundary"))
			{
				multiPartBoundary_ = contentType.munch("^ ;");
				isMultiPart_ = true;
			}
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

	private void byChunkMethod()
	{
		// readChunk yields the buffer whenever possible
		if (!socket.readChunk(overflow, body_))
		{
			disconnect();
		}
	}

	/// Read data from this instance by chunk (Transfer-Encoding).
	auto byChunk()
	{
		enforce(isChunked, __PRETTY_FUNCTION__ ~ " called on instance with no chunked data.");
		return new Generator!(ubyte[])(&byChunkMethod);
	}

	/// Read data from this instance by block (requires Content-Length).
	auto byBlock()
	{
		immutable header = getHeader("Content-Length");
		enforce(!header.empty, __PRETTY_FUNCTION__ ~ " called on instance with no Content-Length header.");

		const length = to!size_t(header);
		return socket.byBlock(overflow, length);
	}
}
