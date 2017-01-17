module http.common;

public import std.socket;

import core.time;

import std.algorithm;
import std.array;
import std.concurrency;
import std.conv;
import std.exception;
import std.range;
import std.string;

// TODO: use a range (or even array) instead of appender for overflow buffers

@safe char[] getln(ref Appender!(char[]) str, const char[] delim)
{
	if (str.data.empty)
	{
		return null;
	}

	auto index = str.data.indexOf(delim);
	if (index < 0)
	{
		return null;
	}

	return str.data[0 .. index + delim.length];
}

@safe char[] overflow(ref Appender!(char[]) input, ref Appender!(char[]) output, const char[] delim)
{
	enforce(input !is output, "input and output must be different!");
	auto result = input.getln(delim);

	if (result.empty)
	{
		return null;
	}

	auto remainder = input.data.length - result.length;

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

void disconnect(ref Socket socket)
{
	if (socket !is null)
	{
		socket.shutdown(SocketShutdown.BOTH);
		socket.close();
	}
}

@safe ptrdiff_t readln(ref Socket socket, ref Appender!(char[]) overflow, out char[] output, const char[] delim = "\r\n")
{
	Appender!(char[]) result;
	char[1024] buffer;
	ptrdiff_t index = -1;
	ptrdiff_t rlength = -1;

	if (!socket.isAlive)
	{
		overflow.clear();
		return 0;
	}

	if (overflow.data == delim)
	{
		overflow.clear();
		return -1;
	}

	result.put(overflow.data);
	overflow.clear();

	auto str = result.overflow(overflow, delim);

	if (str.empty)
	{
		while (index < 0 && socket.isAlive)
		{
			auto length = socket.receive(buffer);
			rlength = length;

			if (!length || length == Socket.ERROR)
			{
				rlength = 0;
				overflow.clear();
				break;
			}

			index = buffer.indexOf(delim);

			if (index < 0)
			{
				result.put(buffer[0 .. length].dup);
			}
			else
			{
				auto i = index + delim.length;
				result.put(buffer[0 .. i].dup);

				if (i < length)
				{
					overflow.put(buffer[i .. length].dup);
				}
			}

			str = result.overflow(overflow, delim);
			if (!str.empty)
			{
				break;
			}
		}
	}

	if (str.empty)
	{
		return rlength;
	}

	enforce(str.count("\r\n") == 1, `Parse failed: more than one line break in output.`);
	enforce(str.endsWith("\r\n"),   `Parse failed: output does not end with line break.`);
	enforce(result.data.empty,      `Unhandled data still remains in the buffer.`);

	output = str[0 .. $ - delim.length];
	return output.length;
}

@safe ptrdiff_t readlen(ref Socket socket, ref Appender!(char[]) overflow, out ubyte[] output, size_t target)
{
	Appender!(char[]) result;
	char[1024] buffer;
	ptrdiff_t rlength = -1;

	auto a = overflow.data[0 .. min($, target)].dup;
	result.put(a);

	if (target < overflow.data.length)
	{
		auto b = overflow.data[target .. $].dup;
		overflow.clear();
		overflow.put(b);
	}
	else
	{
		overflow.clear();
	}

	while (result.data.length < target && socket.isAlive)
	{
		auto length = socket.receive(buffer);
		rlength = length;

		if (!length || length == Socket.ERROR)
		{
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
	return rlength;
}

@trusted ubyte[] readChunk(ref Socket socket, ref Appender!(char[]) overflow)
{
	// TODO: fix invalid utf sequence (string auto decoding sucks!)
	Appender!(char[]) result;

	for (char[] line; socket.readln(overflow, line);)
	{
		if (line.empty)
		{
			continue;
		}

		result.writeln(line);

		ubyte[] buffer;
		auto length = to!size_t(line, 16);
		socket.readlen(overflow, buffer, length + 2);

		yield(cast(ubyte[])(line ~ "\r\n") ~ buffer);
		result.put(buffer);

		if (!length)
		{
			break;
		}
	}

	if (!overflow.data.empty)
	{
		// TODO: check if this even works! (reads trailers (headers))
		for (char[] line; socket.readln(overflow, line);)
		{
			result.writeln(line);
			yield(cast(ubyte[])(line ~ "\r\n"));
		}
	}

	return cast(ubyte[])result.data;
}

@safe void writeln(T, A...)(ref Appender!T output, A args)
{
	foreach (a; args)
	{
		output.put(a);
	}

	output.put("\r\n");
}

@safe void writeln(A...)(ref Socket socket, A args)
{
	Appender!string builder;
	builder.writeln(args);
	socket.send(builder.data);
}
