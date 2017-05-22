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

			char[] data;

			// TODO: send in chunks! This loads entire files into memory before forwarding to the server!
			if (socket.readUntil(start, overflow, data, true) < 1)
			{
				break;
			}
			
			s.sendYield(data);
		}
	}

	void send(ref Appender!(char[]) overflow)
	{
		send(socket, overflow);
	}
}
