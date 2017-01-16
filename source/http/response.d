module http.response;

import core.time;

import std.string;
import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.uni : sicmp;
import std.range;

import http.common;
import http.enums;

// TODO: cookies?

class HttpResponse : HttpInstance
{
private:
	Appender!(char[]) overflow;

public:
	string[string] headers;
	HttpVersion version_;
	int statusCode;
	string statusPhrase;
	ubyte[] body_;

	this(Socket socket, int statusCode = HttpStatus.ok, string statusPhrase = null, HttpVersion version_ = HttpVersion.v1_1)
	{
		super(socket);

		this.statusCode   = statusCode;
		this.statusPhrase = statusPhrase;
		this.version_     = version_;
	}

	// performs case insensitive key lookup
	// TODO: de-dupe (see http.request)
	string getHeader(in string key)
	{
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


	override void clear()
	{
		headers    = null;
		version_   = HttpVersion.v1_1;
		statusCode = HttpStatus.ok;
		body_      = null;
	}

	override void run()
	{
		receive();
	}

	void send(Socket s)
	{
		auto str = toString();
		s.send(cast(ubyte[])str ~ body_);
	}

	override void send()
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

		if (headers.length)
		{
			headers.byKeyValue.each!(x => result.writeln(x.key ~ ": " ~ x.value));
		}

		result.writeln();
		return result.data;
	}

private:
	void receive()
	{
		auto line = socket.readln(overflow);

		if (line.empty)
		{
			disconnect();
			return;
		}

		auto _httpVersion = line.munch("^ ");
		version_ = _httpVersion.toVersion();
		line.munch(" ");

		statusCode = parse!int(line);
		line.munch(" ");

		statusPhrase = to!string(line);

		for (char[] header; !(header = socket.readln(overflow)).empty;)
		{
			auto key = header.munch("^:");
			header.munch(": ");
			auto value = header;
			headers[key.idup] = value.idup;
		}

		auto length = getHeader("Content-Length");
		if (!length.empty)
		{
			body_ = socket.readlen(overflow, to!size_t(length));
			return;
		}

		auto transferEncoding = getHeader("Transfer-Encoding");
		if (!transferEncoding.empty)
		{
			body_ = socket.readChunk(overflow);
		}
	}
}

void badRequest(Socket socket)
{
	auto response = new HttpResponse(socket);
	response.statusCode = HttpStatus.badRequest;
	response.send();
}