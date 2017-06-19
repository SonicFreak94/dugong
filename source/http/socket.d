module http.socket;

public import std.socket;

import core.time;
import std.algorithm;
import std.array;
import std.concurrency;
import std.conv;
import std.exception;
import std.string;

import http.common;
import buffer;
import window;

/// Pulls a whole line out of an $(D Appender!(char[])) and leaves any remaining data.
/// Params:
///		str = An $(D Appender!(char[])) to scan until $(D pattern).
/// 	pattern = Pattern to scan for.
/// Returns: The data if found, else null.
@safe private char[] get(ref Appender!(char[]) str, const char[] pattern)
{
	if (str.data.empty)
	{
		return null;
	}

	auto index = str.data.indexOf(pattern);

	if (index < 0)
	{
		return null;
	}

	return str.data[0 .. index + pattern.length];
}

/**
	Searches for a $(PARAM pattern)-delimited block of data in $(PARAM input)
	and returns it. Excess data is placed in $(PARAM output).

	Params:
		input = The buffer to search in.
		pattern = The block delimiter.
		output = Overflow buffer for excess data.

	Returns:
		The block of data if found, else `null`.
*/
@safe private char[] _overflow(ref Appender!(char[]) input, const char[] pattern, ref Appender!(char[]) output)
{
	enforce(input !is output, "input and output must be different!");
	auto result = input.get(pattern);

	if (result.empty)
	{
		return null;
	}

	const remainder = input.data.length - result.length;

	if (remainder > 0)
	{
		auto index = result.length;
		if (index < input.data.length)
		{
			output.put(input.data[index .. $]);
			input.clear();
		}
	}
	else
	{
		input.clear();
	}

	return result;
}

/// `Socket` wrapper with deterministically allocated, dynamically expanding buffer.
class HttpSocket : Socket
{
private:
	alias BufferT = Buffer!(ubyte, 256 * 1024);

	BufferT _buffer;
	Appender!(char[]) overflow;

public:
	/// For the `accepting` overload.
	pure nothrow @safe this()
	{
		super();
	}

	this(int keepAlive, lazy Duration timeout)
	{
		super(AddressFamily.INET, SocketType.STREAM, ProtocolType.TCP);
		super.blocking = false;

		this.setTimeouts(keepAlive, timeout);
	}

	this(InternetAddress addr, int keepAlive = 5, lazy Duration timeout = 15.seconds)
	{
		super(addr.addressFamily, SocketType.STREAM, ProtocolType.TCP);

		this.setTimeouts(keepAlive, timeout);

		super.blocking = false;
		super.connectAsync(addr);
	}

	this(in string address, ushort port, int keepAlive = 5, lazy Duration timeout = 15.seconds)
	{
		auto addr = new InternetAddress(address, port);
		this(addr, keepAlive, timeout);
	}

	this(AddressFamily af, SocketType type, int keepAlive = 5, lazy Duration timeout = 15.seconds)
	{
		super(af, type);
		super.blocking = false;
		this.setTimeouts(keepAlive, timeout);
	}

	~this()
	{
		disconnect();
	}

	nothrow void disconnect()
	{
		http.common.disconnect(super);
		clear();
	}

	nothrow void clear()
	{
		overflow.clear();

		if (_buffer !is null)
		{
			_buffer.clear();
			_buffer = null;
		}
	}

	override protected pure nothrow @safe HttpSocket accepting()
	{
		return new HttpSocket();
	}

	override @trusted HttpSocket accept()
	{
		return cast(HttpSocket)super.accept();
	}

	/**
		Sets send/receive timeouts on the specified socket.

		Params:
			keepAlive = Keep-alive time.
			timeout   = The send/receive timeout.
	*/
	@safe void setTimeouts(int keepAlive, in Duration timeout)
	{
		super.setOption(SocketOptionLevel.SOCKET, SocketOption.SNDTIMEO, timeout);
		super.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, timeout);
		super.setKeepAlive(keepAlive, keepAlive);
	}

	private void initBuffer()
	{
		if (_buffer is null)
		{
			_buffer = new BufferT();
		}
	}

	ptrdiff_t readBlockUntil(const char[] pattern, bool overflowPattern = false)
	{
		ptrdiff_t result;

		if (overflow.data == pattern)
		{
			overflow.clear();
			return -1;
		}

		auto window = SearchWindow!char(pattern.length);
		Appender!(char[]) _wbuffer;

		if (!overflow.data.empty)
		{
			size_t end;
			bool match;

			foreach (size_t i, char c; overflow.data)
			{
				end = i + 1;
				window.put(c, _wbuffer);

				if (window.match(pattern))
				{
					match = true;
					break;
				}
			}

			if (overflow.data.length <= pattern.length)
			{
				overflow.clear();
			}
			else
			{
				if (!_wbuffer.data.empty)
				{
					yield(cast(ubyte[])_wbuffer.data);
					result = _wbuffer.data.length;
					_wbuffer.clear();
				}

				if (end == overflow.data.length)
				{
					overflow.clear();

					if (match && overflowPattern)
					{
						overflow.put(pattern);
					}
				}
				else
				{
					auto remainder = overflow.data[end .. $].dup;
					overflow.clear();

					if (match && overflowPattern)
					{
						overflow.put(pattern);
					}

					overflow.put(remainder);
				}
			}

			if (match)
			{
				return result + window.length;
			}
		}

		if (!isAlive)
		{
			overflow.clear();
			return 0;
		}

		initBuffer();
		enforce(!blocking, "socket must be non-blocking");

		while (!window.match(pattern) && isAlive)
		{
			auto length = this.receiveAsync(_buffer[]);

			if (!length || length == HttpSocket.ERROR)
			{
				overflow.clear();
				result = -1;
				break;
			}

			_buffer.addLength(length);

			_wbuffer.clear();

			size_t end;
			bool match;

			foreach (size_t i, ubyte b; _buffer[0 .. length])
			{
				end = i + 1;
				window.put(cast(char)b, _wbuffer);

				if (window.match(pattern))
				{
					match = true;
					break;
				}
			}

			if (!_wbuffer.data.empty)
			{
				yield(cast(ubyte[])_wbuffer.data);
				result += _wbuffer.data.length;
			}

			if (match)
			{
				result += window.length;

				if (overflowPattern)
				{
					overflow.put(pattern);
				}

				if (end < length)
				{
					overflow.put(_buffer[end .. $].dup);
				}
			}
		}

		return result;
	}

	Generator!(ubyte[]) byBlockUntil(const char[] pattern, bool overflowPattern = false)
	{
		return new Generator!(ubyte[])(
		{
			readBlockUntil(pattern, overflowPattern);
		});
	}

	/**
		Reads from a socket until the specified pattern is found or the connection times out.

		This is not ideal for data sets that are expected to be large as it buffers all of the
		data until $(PARAM pattern) is encountered.
	
		TODO: Refactor to take in a user provided buffer to rectify data buffering issues.

		Params:
			pattern         = The pattern to search for.
			output          = A buffer to store the data.
			overflowPattern =
				If `true`, put the pattern in the overflow buffer
				instead of discarding it.

		Returns:
			The number of bytes read (including the length of the pattern),
			`0` if the connection has been closed, or `HttpSocket.ERROR` on failure.
	*/
	ptrdiff_t readUntil(const char[] pattern, out char[] output, bool overflowPattern = false)
	{
		Appender!(char[]) result;
		char[] str;
		ptrdiff_t index = -1;
		ptrdiff_t length = -1;

		if (overflow.data == pattern)
		{
			overflow.clear();
			return -1;
		}

		if (!overflow.data.empty)
		{
			result.put(overflow.data);
			overflow.clear();
			str = result._overflow(pattern, overflow);
		}

		void check()
		{
			enforce(str.endsWith(pattern),   "Parse failed: output does not end with pattern.");
			enforce(str.count(pattern) == 1, "Parse failed: more than one pattern in output.");
			enforce(result.data.empty,       "Unhandled data still remains in the buffer.");
			output = str[0 .. $ - pattern.length];
		}

		if (!str.empty)
		{
			check();
			return str.length;
		}

		if (!isAlive)
		{
			overflow.clear();
			return 0;
		}

		initBuffer();
		enforce(!blocking, "socket must be non-blocking");

		while (index < 0 && isAlive)
		{
			length = this.receiveAsync(_buffer[]);

			if (!length || length == HttpSocket.ERROR)
			{
				// maybe send?
				overflow.clear();
				break;
			}

			_buffer.addLength(length);

			index = (cast(char[])_buffer[0 .. length]).indexOf(pattern);

			if (index < 0)
			{
				result.put(_buffer[0 .. length].dup);
			}
			else
			{
				auto i = index + pattern.length;
				result.put(_buffer[0 .. i].dup);

				if (i < length)
				{
					overflow.put(_buffer[(overflowPattern ? index : i) .. length].dup);
				}
			}

			str = result._overflow(pattern, overflow);
			if (!str.empty)
			{
				break;
			}
		}

		if (str.empty)
		{
			return length;
		}

		check();
		return str.length;
	}

	/**
		Attemps to read a whole line from a socket.

		Note that this buffers the data until an entire line is available, so
		it should only be used on data sets that are expected to be small.

		Params:
			output = An output buffer to store the line.

		Returns:
			The number of bytes read (including the length of the line break),
			`0` if the connection has been closed, or `HttpSocket.ERROR` on failure.

		See_Also: readUntil
	*/
	ptrdiff_t readln(out char[] output)
	{
		return readUntil(HTTP_BREAK, output);
	}

	/**
		Reads and yields each line from the socket as they become available.

		Params:
			socket   = The socket to read from.
			overflow = Overflow buffer to store excess data.

		Returns:
			`Generator!(char[])`
	*/
	Generator!(char[]) byLine()
	{
		return new Generator!(char[])(
		{
			for (char[] line; this.readln(line) > 0;)
			{
				yield(line);
			}
		});
	}

	/**
		Attempts to read a specified number of bytes from a socket and yields
		each block of data as it is received until the target size is reached.

		Params:
			socket   = The socket to read from.
			overflow = Overflow buffer for excess data.
			target   = The target chunk size.

		Returns:
			The number of bytes read, `0` if the connection has been closed,
			or `HttpSocket.ERROR` on failure.
	*/
	ptrdiff_t readBlock(ptrdiff_t target)
	{
		ptrdiff_t result;

		auto arr = overflow.data[0 .. min($, target)].representation;
		yield(arr);
		result += arr.length;

		if (target < overflow.data.length)
		{
			// .dup prevents a crash related to overlapping
			arr = overflow.data[target .. $].representation.dup;
			overflow.clear();
			overflow.put(arr);
		}
		else
		{
			overflow.clear();
		}

		initBuffer();

		while (result < target)
		{
			auto length = this.receiveAsync(_buffer[]);

			if (!length || length == HttpSocket.ERROR)
			{
				overflow.clear();
				return length;
			}

			_buffer.addLength(length);

			auto remainder = target - result;
			arr = _buffer[0 .. min(length, remainder)];
			result += arr.length;
			yield(arr);

			if (remainder < length)
			{
				overflow.put(_buffer[remainder .. length].dup);
			}
		}

		enforce(result == target, "retrieved does not match target size");
		return result;
	}
	/// Ditto
	Generator!(ubyte[]) byBlock(ptrdiff_t target)
	{
		return new Generator!(ubyte[])(
		{
			readBlock(target);
		});
	}

	/**
		Reads a "Transfer-Encoding: chunked" body from a $(D HttpSocket).

		Params:
			socket   = The socket to read from.
			overflow = Overflow buffer for excess data.
			output   = A buffer to store the chunk.

		Returns:
			The number of bytes read, `0` if the connection has been closed,
			or `HttpSocket.ERROR` on failure.
	*/
	ptrdiff_t readChunk(out ubyte[] output)
	{
		Appender!(char[]) result;
		ptrdiff_t rlength;

		for (char[] line; this.readln(line) > 0;)
		{
			if (line.empty)
			{
				continue;
			}

			yield((line ~ HTTP_BREAK).representation);
			result.writeln(line);

			auto length = to!ptrdiff_t(line, 16);

			foreach (block; byBlock(length + 2))
			{
				yield(block);
				result.put(block);
			}

			if (!length || line.empty)
			{
				break;
			}
		}

		if (!overflow.data.empty)
		{
			// TODO: check if this even works! (reads trailers (headers))
			for (char[] line; (rlength = this.readln(line)) > 0;)
			{
				result.writeln(line);
				yield((line ~ HTTP_BREAK).representation);
			}
		}

		output = result.data.representation.dup;
		return rlength;
	}
}
