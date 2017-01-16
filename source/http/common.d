module http.common;

public import std.socket;

import core.time;
import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.string;
import std.range;

public import http.enums;

// TODO: interface (run, connected, etc)
// TODO: outbound socket pool

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

@safe void disconnect(Socket socket)
{
	socket.shutdown(SocketShutdown.BOTH);
	socket.close();
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

@safe char[] readln(Socket socket, ref Appender!(char[]) overflow, const char[] delim = "\r\n")
{
	Appender!(char[]) result;
	char[1024] buffer;
	ptrdiff_t index = -1;

	if (!socket.isAlive)
	{
		return null;
	}

	if (overflow.data == delim)
	{
		overflow.clear();
		return null;
	}

	result.put(overflow.data);
	overflow.clear();

	auto str = result.overflow(overflow, delim);

	if (str.empty)
	{
		while (index < 0 && socket.isAlive)
		{
			auto length = socket.receive(buffer);

			if (!length || length == Socket.ERROR)
			{
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
		return null;
	}

	enforce(str.count("\r\n") == 1, `Parse failed: more than one line break in output.`);
	enforce(str.endsWith("\r\n"),   `Parse failed: output does not end with line break.`);
	enforce(result.data.empty,      `Unhandled data still remains in the buffer.`);

	return str[0 .. $ - delim.length];
}

@safe ubyte[] readlen(Socket socket, ref Appender!(char[]) overflow, size_t target)
{
	Appender!(char[]) result;
	char[1024] buffer;

	auto a = overflow.data[0 .. min($, target)];
	result.put(a);

	if (target < overflow.data.length)
	{
		auto b = overflow.data[target .. $].idup;
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

		if (!length || length == Socket.ERROR)
		{
			break;
		}

		auto remainder = target - result.data.length;
		result.put(buffer[0 .. min(length, remainder)]);

		if (remainder < length)
		{
			overflow.put(buffer[remainder .. $]);
		}
	}

	return result.data.empty ? null : cast(ubyte[])result.data;
}

@trusted ubyte[] readChunk(Socket socket, ref Appender!(char[]) overflow)
{
	// TODO: fix invalid utf sequence (string auto decoding sucks!)
	// TODO: send chunks as they're received
	Appender!(char[]) result;

	for (char[] line; !(line = socket.readln(overflow)).empty;)
	{
		for (int i = 0; i < line.length; i++)
		{
			result.put(line[i]);
		}
		result.writeln();

		auto length = to!size_t(line, 16);
		auto buffer = socket.readlen(overflow, length + 2);
		result.put(cast(char[])buffer);

		if (!length)
		{
			break;
		}
	}

	// TODO: check if this even works! (reads trailers (headers))
	for (char[] line; !(line = socket.readln(overflow)).empty;)
	{
		result.writeln(line);
	}

	result.writeln();

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

@safe void writeln(A...)(Socket socket, A args)
{
	Appender!string builder;
	builder.writeln(args);
	socket.send(builder.data);
}

// TODO: move to separate module:

interface IHttpInstance
{
	bool connected();
	void disconnect();
	string getHeader(in string key);
	void run();
	void receive();
	void send(Socket s);
	void send();
	void clear();
}

abstract class HttpInstance : IHttpInstance
{
protected:
	Socket socket;
	Appender!(char[]) overflow;
	HttpVersion version_;
	string[string] headers;
	ubyte[] body_;

public:
	this(Socket socket, lazy Duration timeout = 15.seconds)
	{
		enforce(socket.isAlive, "socket must be connected!");

		this.socket = socket;
		this.socket.setOption(SocketOptionLevel.SOCKET, SocketOption.SNDTIMEO, timeout);
		this.socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, timeout);
		this.socket.blocking = true;
	}

	final bool connected()
	{
		return socket.isAlive();
	}

	void disconnect()
	{
		socket.disconnect();
		clear();
	}

	final string getHeader(in string key)
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
			return takeOne(search).front[1];
		}

		return null;
	}

	void clear()
	{
		overflow.clear();
		version_ = HttpVersion.v1_1;
		headers  = null;
		body_    = null;
	}
}
