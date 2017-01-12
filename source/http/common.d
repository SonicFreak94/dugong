module http.common;

public import std.socket;
debug import std.stdio;

import std.array;
import std.string;

enum Method
{
	nope
}

// TODO: interface (run, connected, etc)
// TODO: outbound socket pool

char[] getln(ref Appender!(char[]) str, const char[] delim = "\r\n")
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

	auto data = str.data;
	str.clear();

	auto start = index + delim.length;
	if (start < data.length)
	{
		str = appender(data[start .. $]);
		debug stderr.writeln(str.data);
	}

	auto result = data[0 .. index];
	debug stderr.writeln(result);
	return result;
}

void disconnect(Socket socket)
{
	socket.shutdown(SocketShutdown.BOTH);
	socket.close();
}

char[] readln(Socket socket, ref Appender!(char[]) overflow, const char[] delim = "\r\n")
{
	Appender!(char[]) result;
	char[8] buffer;
	ptrdiff_t index = -1;
	bool received;

	if (!socket.isAlive)
	{
		return null;
	}

	auto tmp = overflow.getln(delim);
	if (!tmp.empty)
	{
		return tmp;
	}

	result.put(overflow.data);
	overflow.clear();

	while (index < 0 && socket.isAlive)
	{
		auto length = socket.receive(buffer);

		if (length == Socket.ERROR)
		{
			if (wouldHaveBlocked() && !received)
			{
				continue;
			}

			break;
		}

		if (!length)
		{
			if (!wouldHaveBlocked())
			{
				break;
			}

			if (!received)
			{
				continue;
			}
		}
		
		received = true;
		index = buffer.indexOf(delim);
		if (index < 0)
		{
			result.put(buffer[0 .. length]);
			continue;
		}
		else
		{
			index += delim.length;
			result.put(buffer[0 .. index]);
		}

		if (index < length)
		{
			overflow.put(buffer[index .. length]);
		}
	}

	result.put(overflow.data);
	debug stderr.writeln("Result: ", result.data);
	debug stderr.writeln("Overflow: ", overflow.data);
	return result.getln(delim);
}

class Request
{
private:
	Socket socket;

public:
	Method method;
	string requestUrl;
	string httpVersion;
	string[string] headers;
	
	this(Socket socket)
	{
		this.socket = socket;
		this.socket.blocking = false;
	}
	
	@property auto connected() const
	{
		return socket.isAlive;
	}
	
	bool run()
	{
		char[1024] buffer;
		Appender!(char[]) overflow;

		char[] _method;

		do
		{
			_method = socket.readln(overflow);
			debug stderr.writefln("[%u] %s", _method.length, _method);
		} while (!_method.empty);

		socket.disconnect();
		return false;
	}
}

class Response
{

}
