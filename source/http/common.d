module http.common;

public import std.socket;
debug import std.stdio;

import core.time;
import std.array;
import std.exception;
import std.string;

enum Method
{
	nope
}

// TODO: interface (run, connected, etc)
// TODO: outbound socket pool

char[] getln(ref Appender!(char[]) str, const char[] delim)
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

void disconnect(Socket socket)
{
	socket.shutdown(SocketShutdown.BOTH);
	socket.close();
}

debug void writedbg(in char[] str)
{
	foreach (c; str)
	{
		switch (c)
		{
			case '\r':
				stderr.write("\\CR");
				break;
			case '\n':
				stderr.write("\\LF");
				break;
			default:
				stderr.write(c);
				break;
		}
	}
}

debug void writedbg(in Appender!(char[]) str)
{
	writedbg(str.data);
}

char[] overflow(ref Appender!(char[]) input, ref Appender!(char[]) output, const char[] delim)
{
	enforce(!(input is output), "input and output must be different!");
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

char[] readln(Socket socket, ref Appender!(char[]) overflow, const char[] delim = "\r\n")
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

	debug
	{
		stderr.write("Final Result: ");
		writedbg(str);
		stderr.writeln();

		stderr.write("   Remainder: ");
		writedbg(result);
		stderr.writeln();

		stderr.write("    Overflow: ");
		writedbg(overflow);
		stderr.writeln();
		stderr.writeln();
	}

	if (str.empty)
	{
		return null;
	}

	enforce(str.count("\r\n") == 1, `Parse failed: two line breaks present.`);
	enforce(str.endsWith("\r\n"), `Parse failed: output does not end with line break.`);
	enforce(result.data.empty, `Unhandled data still remains in the buffer.`);

	return str[0 .. $ - delim.length];
}

class Request
{
private:
	Socket socket;
	Appender!(char[]) overflow;

public:
	Method method;
	string requestUrl;
	string httpVersion;
	string[string] headers;
	
	this(Socket socket)
	{
		enforce(socket.isAlive);
		this.socket = socket;
		this.socket.setOption(SocketOptionLevel.SOCKET, SocketOption.SNDTIMEO, 15.seconds);
		this.socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, 15.seconds);
	}
	
	@property auto connected() const
	{
		return socket.isAlive;
	}

	void disconnect()
	{
		overflow.clear();
		socket.disconnect();
	}
	
	bool run()
	{
		char[] str;

		try
		{
			do
			{
				str = socket.readln(overflow);
			} while (!str.empty);
		}
		catch (Exception ex)
		{
			stderr.writeln(ex.msg);
		}

		// TODO: parse the things and populate fields

		return false;
	}
}

class Response
{

}
