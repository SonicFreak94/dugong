module http.multipart;

import std.array;
import std.exception;
import std.string;

import http.common;

/// Handles multipart POST data from clients.
class HttpMultiPart
{
private:
	Socket socket;
	string boundary;

public:
	this(Socket socket, in string boundary)
	{
		this.socket = socket;
		this.boundary = boundary;
	}

	// HACK: overflow is for the receiving socket, NOT s
	void send(Socket s, ref Appender!(char[]) overflow)
	{
		immutable start = "--" ~ boundary;
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

	void send(ref Appender!(char[]) overflow)
	{
		send(socket, overflow);
	}
}
