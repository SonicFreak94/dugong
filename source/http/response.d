module http.response;

import core.time;

import std.string;
import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.uni : sicmp;
import std.range;
import std.concurrency;

import http.instance;
import http.common;
import http.enums;

void badRequest(Socket socket)
{
	auto response = new HttpResponse(socket);
	response.statusCode = HttpStatus.badRequest;
	response.send();
}

class HttpResponse : HttpInstance
{
public:
	int statusCode;
	string statusPhrase;

	this(Socket socket, int statusCode = HttpStatus.ok, string statusPhrase = null, HttpVersion version_ = HttpVersion.v1_1)
	{
		super(socket);

		this.statusCode   = statusCode;
		this.statusPhrase = statusPhrase;
		this.version_     = version_;
	}

	override void clear()
	{
		super.clear();
		statusCode   = HttpStatus.ok;
		statusPhrase = null;
	}

	void run()
	{
		throw new Exception("Not implemented");
	}

	void send(Socket s)
	{
		auto str = toString();

		if (body_.empty)
		{
			s.send(str);

			if (isChunked)
			{
				foreach (buffer; getChunks())
				{
					s.send(buffer);
				}
			}
		}
		else
		{
			s.send(cast(ubyte[])str ~ body_);
		}
	}

	void send()
	{
		send(socket);
	}

	override string toString()
	{
		Appender!string result;

		result.writeln(version_.toString(),
			' ', to!string(statusCode),
			' ', statusPhrase.empty ? (cast(HttpStatus)statusCode).toString() : statusPhrase
		);

		auto headerString = super.toHeaderString();
		if (!headerString.empty)
		{
			result.writeln(headerString);
		}

		result.writeln();
		return result.data;
	}

	bool receive()
	{
		char[] line;
		if (!socket.readln(overflow, line) && line.empty)
		{
			disconnect();
			return false;
		}

		if (line.empty)
		{
			return false;
		}

		auto _httpVersion = line.munch("^ ");
		version_ = _httpVersion.toVersion();
		line.munch(" ");

		statusCode = parse!int(line);
		line.munch(" ");

		statusPhrase = line.idup;

		super.parseHeaders();
		return true;
	}

	Generator!(ubyte[]) getChunks()
	{
		enforce(isChunked, "getChunks() called on response with no chunked data.");

		return new Generator!(ubyte[])(
		{
			// readChunk yields the buffer whenever possible
			body_ = socket.readChunk(overflow);
		});
	}
}
