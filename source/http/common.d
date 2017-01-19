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

// TODO: use a range (or even array) instead of appender for overflow buffers

/// Sleeps the thread and then yields.
void wait()
{
	Thread.sleep(1.msecs);
	yield();
}

/// Represents an HTTP EOL
const enum HTTP_BREAK = "\r\n";

/// Pulls a whole line out of an $(D Appender!(char[])) and leaves any remaining data.
/// Params:
///		str = An $(D Appender!(char[])) to scan for a line.
/// Returns: The line if found, else null.
@safe char[] getln(ref Appender!(char[]) str)
{
	if (str.data.empty)
	{
		return null;
	}

	auto index = str.data.indexOf(HTTP_BREAK);
	if (index < 0)
	{
		return null;
	}

	return str.data[0 .. index + HTTP_BREAK.length];
}

/// Pulls a whole line out of the input $(D Appender!(char[])) if possible, and puts remaining
/// data into the output $(D Appender!(char[])).
/// Returns: The line if found, else null.
@safe char[] overflow(ref Appender!(char[]) input, ref Appender!(char[]) output)
{
	enforce(input !is output, "input and output must be different!");
	auto result = input.getln();

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

/// Calls $(D shutdown(SocketShutdown.BOTH)) on $(D socket) before closing it.
@safe void disconnect(ref Socket socket)
{
	if (socket !is null)
	{
		socket.shutdown(SocketShutdown.BOTH);
		socket.close();
	}
}

/// Same as $(D Socket.receive), but for non-blocking sockets. Calls $(D yield) until 
/// there is data to be received. The connection will time out just like a blocking socket.
ptrdiff_t receiveYield(ref Socket socket, void[] buffer)
{
	if (socket is null || !socket.isAlive)
	{
		return 0;
	}

	ptrdiff_t length = -1;
	const start = MonoTime.currTime;
	Duration timeout;

	socket.getOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, timeout);

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
			continue;
		}
	} while (length < 1 && MonoTime.currTime - start < timeout);

	return length;
}

/// Same as $(D Socket.send), but for non-blocking sockets. Calls $(D yield) every
/// loop until the data is fully sent, or until the connection times out.
ptrdiff_t sendYield(ref Socket socket, const(void)[] buffer)
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
			wait();
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

/// Attemps to read a whole line from a socket.
ptrdiff_t readln(ref Socket socket, ref Appender!(char[]) overflow, out char[] output)
{
	enforce(!socket.blocking, "socket must not be blocking");
	Appender!(char[]) result;
	char[1024] buffer;
	ptrdiff_t index = -1;
	ptrdiff_t length = -1;

	if (!socket.isAlive)
	{
		overflow.clear();
		return 0;
	}

	if (overflow.data == HTTP_BREAK)
	{
		overflow.clear();
		return -1;
	}

	result.put(overflow.data);
	overflow.clear();

	auto str = result.overflow(overflow);

	if (str.empty)
	{
		while (index < 0 && socket.isAlive)
		{
			length = socket.receiveYield(buffer);

			if (!length || length == Socket.ERROR)
			{
				// maybe send?
				overflow.clear();
				break;
			}

			index = buffer.indexOf(HTTP_BREAK);

			if (index < 0)
			{
				result.put(buffer[0 .. length].dup);
			}
			else
			{
				auto i = index + HTTP_BREAK.length;
				result.put(buffer[0 .. i].dup);

				if (i < length)
				{
					overflow.put(buffer[i .. length].dup);
				}
			}

			str = result.overflow(overflow);
			if (!str.empty)
			{
				break;
			}
		}
	}

	if (str.empty)
	{
		return length;
	}

	enforce(str.endsWith(HTTP_BREAK),   `Parse failed: output does not end with line break.`);
	enforce(str.count(HTTP_BREAK) == 1, `Parse failed: more than one line break in output.`);
	enforce(result.data.empty,          `Unhandled data still remains in the buffer.`);

	output = str[0 .. $ - HTTP_BREAK.length];
	return output.length;
}

/// Attempts to read a specified number of bytes from a socket.
ptrdiff_t readlen(ref Socket socket, ref Appender!(char[]) overflow, out ubyte[] output, size_t target)
{
	Appender!(char[]) result;
	char[1024] buffer;
	ptrdiff_t length = -1;

	result.put(overflow.data[0 .. min($, target)]);

	if (target < overflow.data.length)
	{
		// .dup prevents a crash related to overlapping
		auto arr = overflow.data[target .. $].dup;
		overflow.clear();
		overflow.put(arr);
	}
	else
	{
		overflow.clear();
	}

	while (result.data.length < target && socket.isAlive)
	{
		length = socket.receiveYield(buffer);

		if (!length || length == Socket.ERROR)
		{
			// maybe send?
			overflow.clear();
			break;
		}

		auto remainder = target - result.data.length;
		result.put(buffer[0 .. min(length, remainder)].dup);

		if (remainder < length)
		{
			overflow.put(buffer[remainder .. length].dup);
		}
	}

	output = result.data.empty ? null : cast(ubyte[])result.data;
	return length;
}

/// Reads a "Transfer-Encoding: chunked" body from a $(D Socket).
/// Returns: The number of bytes actually received, $(D 0) if the remote side
/// has closed the connection, or $(D Socket.ERROR) on failure.
@trusted ptrdiff_t readChunk(ref Socket socket, ref Appender!(char[]) overflow, out ubyte[] data)
{
	Appender!(char[]) result;
	ptrdiff_t rlength;

	for (char[] line; (rlength = socket.readln(overflow, line)) > 0;)
	{
		if (line.empty)
		{
			continue;
		}

		result.writeln(line);

		ubyte[] buffer;
		auto length = to!size_t(line, 16);
		socket.readlen(overflow, buffer, length + 2);

		yield(cast(ubyte[])(line ~ HTTP_BREAK) ~ buffer); // trusted
		result.put(buffer);

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
			yield(cast(ubyte[])(line ~ HTTP_BREAK)); // trusted
		}
	}

	data = (cast(ubyte[])result.data).dup;
	return rlength;
}

/// Convenience function for writing lines to $(D Appender)
@safe void writeln(T, A...)(ref Appender!T output, A args)
{
	foreach (a; args)
	{
		output.put(a);
	}

	output.put(HTTP_BREAK);
}
/// Convenience function for writing lines to $(D Socket)
@safe auto writeln(A...)(ref Socket socket, A args)
{
	Appender!string builder;
	builder.writeln(args);
	return socket.sendYield(builder.data);
}
