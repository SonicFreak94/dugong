module http.common;

public import std.socket;

import core.thread;
import core.time;

import std.algorithm;
import std.array;
import std.concurrency;
import std.conv;
import std.exception;
import std.range;
import std.string;

import window;

// TODO: make all socket methods part of a derived socket type to reduce allocations
// TODO: use a range (or even array) instead of appender for overflow buffers
// TODO: consider uninitializedArray for local buffers

/// Sleeps the thread and then yields.
void wait()
{
	Thread.sleep(1.msecs);
	yield();
}

/// Represents an HTTP EOL
private const enum HTTP_BREAK = "\r\n";
/// Receive buffer size (1MiB)
const enum HTTP_BUFFLEN = 1 * 1024 * 1024;
/// (thread-local) static buffer for receiving data.
private ubyte[HTTP_BUFFLEN] _buffer;

/**
	Calls `Socket.shutdown` with the parameter `SocketShutdown.BOTH` on the specified
	socket and closes the socket.

	Params:
		socket = The socket to disconnect.
*/
void disconnect(Socket socket)
{
	if (socket !is null)
	{
		socket.shutdown(SocketShutdown.BOTH);
		socket.close();
	}
}

/**
	Sets send/receive timeouts on the specified socket.

	Params:
		socket    = The socket whose timeouts are to be set.
		keepAlive = Keep-alive time.
		timeout   = The send/receive timeout.
*/
void setTimeouts(Socket socket, int keepAlive, in Duration timeout)
{
	if (socket !is null)
	{
		socket.setOption(SocketOptionLevel.SOCKET, SocketOption.SNDTIMEO, timeout);
		socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, timeout);
		socket.setKeepAlive(keepAlive, keepAlive);
	}
}

/**
	Pseudo-blocking version of `Socket.receive` for non-blocking
	sockets which calls `yield` until data has been received or
	the connection is terminated.

	Params:
		socket = The socket to read from.
		buffer = Output buffer to store the received data.

	Returns:
		The number of bytes read, `0` if the connection has been closed,
		or `Socket.ERROR` on failure.
*/
ptrdiff_t receiveYield(Socket socket, void[] buffer)
{
	if (socket is null || !socket.isAlive)
	{
		return 0;
	}

	ptrdiff_t length = -1;
	const start = MonoTime.currTime;
	Duration timeout;

	socket.getOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, timeout);
	enforce(timeout >= 1.msecs, "SocketOption.RCVTIMEO must be at least 1ms");

	do
	{
		length = socket.receive(buffer);

		if (length == Socket.ERROR)
		{
			if (!wouldHaveBlocked())
			{
				return 0;
			}

			wait();
		}
	} while (length < 1 && MonoTime.currTime - start < timeout);

	return length;
}

/**
	Pseudo-blocking version of `Socket.send` for non-blocking
	sockets which calls `yield` until data has been sent or
	the connection is terminated.

	Params:
		socket = The socket to write to.
		buffer = The buffer to write to the socket.

	Returns:
		The number of bytes read, `0` if the connection has been closed,
		or `Socket.ERROR` on failure.
*/
ptrdiff_t sendYield(Socket socket, const(void)[] buffer)
{
	if (socket is null || !socket.isAlive)
	{
		return 0;
	}

	ptrdiff_t result, sent;
	auto start = MonoTime.currTime;
	Duration timeout;

	socket.getOption(SocketOptionLevel.SOCKET, SocketOption.SNDTIMEO, timeout);

	do
	{
		sent = socket.send(buffer[result .. $]);

		if (sent == Socket.ERROR)
		{
			if (!wouldHaveBlocked())
			{
				return 0;
			}
		}
		else if (sent > 0)
		{
			result += sent;
			start = MonoTime.currTime;
		}

		wait();
	} while (socket.isAlive && result < buffer.length && sent < 1 && MonoTime.currTime - start < timeout);

	return result;
}

/// Pulls a whole line out of an $(D Appender!(char[])) and leaves any remaining data.
/// Params:
///		str = An $(D Appender!(char[])) to scan until $(D pattern).
/// 	pattern = Pattern to scan for.
/// Returns: The data if found, else null.
char[] get(ref Appender!(char[]) str, const char[] pattern)
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
char[] overflow(ref Appender!(char[]) input, const char[] pattern, ref Appender!(char[]) output)
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

ptrdiff_t readBlockUntil(Socket socket, const char[] pattern, ref Appender!(char[]) overflow,
	bool overflowPattern = false)
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

	if (socket is null || !socket.isAlive)
	{
		overflow.clear();
		return 0;
	}

	enforce(!socket.blocking, "socket must be non-blocking");

	while (!window.match(pattern) && socket.isAlive)
	{
		auto length = socket.receiveYield(_buffer);

		if (!length || length == Socket.ERROR)
		{
			overflow.clear();
			result = -1;
			break;
		}

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

Generator!(ubyte[]) byBlockUntil(Socket socket, const char[] pattern, ref Appender!(char[]) overflow,
	bool overflowPattern = false)
{
	return new Generator!(ubyte[])(
	{
		socket.readBlockUntil(pattern, overflow, overflowPattern);
	});
}

/**
	Reads from a socket until the specified pattern is found or the connection times out.

	This is not ideal for data sets that are expected to be large as it buffers all of the
	data until $(PARAM pattern) is encountered.
	
	TODO: Refactor to take in a user provided buffer to rectify data buffering issues.

	Params:
		socket          = The socket to read from.
		pattern         = The pattern to search for.
		overflow        = Overflow buffer to store excess data.
		output          = A buffer to store the data.
		overflowPattern =
			If `true`, put the pattern in the overflow buffer
			instead of discarding it.

	Returns:
		The number of bytes read (including the length of the pattern),
		`0` if the connection has been closed, or `Socket.ERROR` on failure.
*/
ptrdiff_t readUntil(Socket socket, const char[] pattern, ref Appender!(char[]) overflow,
		out char[] output, bool overflowPattern = false)
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
		str = result.overflow(pattern, overflow);
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

	if (socket is null || !socket.isAlive)
	{
		overflow.clear();
		return 0;
	}

	enforce(!socket.blocking, "socket must be non-blocking");

	while (index < 0 && socket.isAlive)
	{
		length = socket.receiveYield(_buffer);

		if (!length || length == Socket.ERROR)
		{
			// maybe send?
			overflow.clear();
			break;
		}

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

		str = result.overflow(pattern, overflow);
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
		socket   = The socket to read from.
		overflow = Overflow buffer to store excess data.
		output   = An output buffer to store the line.

	Returns:
		The number of bytes read (including the length of the line break),
		`0` if the connection has been closed, or `Socket.ERROR` on failure.

	See_Also: readUntil
*/
ptrdiff_t readln(Socket socket, ref Appender!(char[]) overflow, out char[] output)
{
	return readUntil(socket, HTTP_BREAK, overflow, output);
}

/**
	Reads and yields each line from the socket as they become available.

	Params:
		socket   = The socket to read from.
		overflow = Overflow buffer to store excess data.

	Returns:
		`Generator!(char[])`
*/
Generator!(char[]) byLine(Socket socket, ref Appender!(char[]) overflow)
{
	return new Generator!(char[])(
	{
		for (char[] line; socket.readln(overflow, line) > 0;)
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
		or `Socket.ERROR` on failure.
*/
ptrdiff_t readBlock(Socket socket, ref Appender!(char[]) overflow, ptrdiff_t target)
{
	ptrdiff_t result;

	auto arr = overflow.data[0 .. min($, target)].representation.dup;
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

	while (result < target)
	{
		auto length = socket.receiveYield(_buffer);

		if (!length || length == Socket.ERROR)
		{
			overflow.clear();
			return length;
		}

		auto remainder = target - result;
		arr = _buffer[0 .. min(length, remainder)].dup;
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
Generator!(ubyte[]) byBlock(Socket socket, ref Appender!(char[]) overflow, ptrdiff_t target)
{
	return new Generator!(ubyte[])(
	{
		socket.readBlock(overflow, target);
	});
}

/**
	Reads a "Transfer-Encoding: chunked" body from a $(D Socket).

	Params:
		socket   = The socket to read from.
		overflow = Overflow buffer for excess data.
		output   = A buffer to store the chunk.

	Returns:
		The number of bytes read, `0` if the connection has been closed,
		or `Socket.ERROR` on failure.
*/
ptrdiff_t readChunk(Socket socket, ref Appender!(char[]) overflow, out ubyte[] output)
{
	Appender!(char[]) result;
	ptrdiff_t rlength;

	for (char[] line; socket.readln(overflow, line) > 0;)
	{
		if (line.empty)
		{
			continue;
		}

		yield((line ~ HTTP_BREAK).representation.dup);
		result.writeln(line);

		auto length = to!ptrdiff_t(line, 16);

		foreach (block; socket.byBlock(overflow, length + 2))
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
		for (char[] line; (rlength = socket.readln(overflow, line)) > 0;)
		{
			result.writeln(line);
			yield((line ~ HTTP_BREAK).representation.dup);
		}
	}

	output = result.data.representation.dup;
	return rlength;
}

/**
	Peek at incoming data on the specified `Socket`.

	Params:
		socket = The socket to read from.
		buffer = The buffer to store the peeked data.

	Returns:
		The number of bytes read, `0` if the connection has been closed,
		or `Socket.ERROR` on failure.
*/
ptrdiff_t peek(Socket socket, void[] buffer)
{
	return socket.receive(buffer, SocketFlags.PEEK);
}

/**
	Convenience function for writing lines to `Appender`
	
	Params:
		output = The appender to write the line to.
		args = Arguments to add to the line.`
*/
void writeln(T, A...)(ref Appender!T output, A args)
{
	foreach (a; args)
	{
		output.put(a);
	}

	output.put(HTTP_BREAK);
}
/**
	Convenience function for writing lines to a `Socket``

	Params:
		socket = The socket to write the line to.
		args = Arguments to add to the line.
*/
auto writeln(A...)(Socket socket, A args)
{
	Appender!string builder;
	builder.writeln(args);
	return socket.sendYield(builder.data);
}
