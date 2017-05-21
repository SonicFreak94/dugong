module http.multipart;

import std.array;
import std.exception;
import std.string;

import http.common;

///
class HttpMultiPart
{
private:
	Appender!(char[]) overflow;
	Socket socket;
	string boundary;
	string[string] headers;

public:
	this(Socket socket, in string boundary)
	{
		this.socket = socket;
		this.boundary = boundary;
	}

	bool receive()
	{
		foreach (line; socket.byLine(overflow))
		{
			if (line.empty)
			{
				break;
			}

			auto key = line.munch("^:").idup;
			line.munch(": ");
			headers[key] = line.idup;
		}

		return !!headers.length;
	}

	void send(Socket s)
	{
		/*
			TODO:
				- get starting boundary(?)
				- get all data until next boundary
				- for each boundary, check if closing boundary
		*/

		immutable start = "--" ~ boundary;
		immutable end = start ~ "--";

		while (true)
		{
			string[string] _headers;
			char[] _boundary;

			if (socket.readln(overflow, _boundary) < 1)
			{
				break;
			}

			enforce(_boundary.startsWith(start));
			s.writeln(_boundary);

			if (_boundary == end)
			{
				break;
			}

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

			char[] data;
			if (socket.readUntil(start, overflow, data) < 1)
			{
				break;
			}
			
			s.sendYield(data);
		}
	}

	void send()
	{
		send(socket);
	}
}
