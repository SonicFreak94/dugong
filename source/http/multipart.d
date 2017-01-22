module http.multipart;

import std.array;
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
	}

	void send()
	{
		send(socket);
	}
}
