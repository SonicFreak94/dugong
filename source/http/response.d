module http.response;

import core.time;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.range;
import std.string;
import std.uni : sicmp;

import http.instance;
import http.common;
import http.enums;

nothrow void sendResponse(ref Socket socket, int statusCode, string statusPhrase = null)
{
	try
	{
		auto request = new HttpResponse(socket, statusCode, statusPhrase);
		request.send();
	}
	catch (Throwable)
	{
		// ignored
	}
}

// Shorthand for sendResponse
nothrow void sendBadRequest(ref Socket socket)
{
	socket.sendResponse(HttpStatus.badRequest);
}

// Shorthand for sendResponse
nothrow void sendNotFound(ref Socket socket)
{
	socket.sendResponse(HttpStatus.notFound);
}

class HttpResponse : HttpInstance
{
public:
	int statusCode;
	string statusPhrase;

	this(Socket socket, bool hasBody,
		 int statusCode = HttpStatus.ok, string statusPhrase = null, HttpVersion version_ = HttpVersion.v1_1)
	{
		super(socket, hasBody);

		this.statusCode   = statusCode;
		this.statusPhrase = statusPhrase;
		this.version_     = version_;
	}

	this(Socket socket,
		 int statusCode = HttpStatus.ok, string statusPhrase = null, HttpVersion version_ = HttpVersion.v1_1)
	{
		this(socket, true, statusCode, statusPhrase, version_);
	}

	override void clear()
	{
		super.clear();
		statusCode = HttpStatus.none;
		statusPhrase = null;
	}

	void run()
	{
		throw new Exception("Not implemented");
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
		clear();

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
		debug import std.stdio;
		debug synchronized stderr.writeln(toString());
		return true;
	}
}
