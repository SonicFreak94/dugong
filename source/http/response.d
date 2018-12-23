module http.response;

import core.time;

import std.algorithm;
import std.array;
import std.ascii : isWhite;
import std.conv;
import std.exception;
import std.range;
import std.string;
import std.uni : sicmp;
import std.utf : byCodeUnit;

import http.common;
import http.enums;
import http.instance;
import http.socket;

/// Convenience function which constructs $(D HttpResponse) with
/// the given status code and immediately sends it.
nothrow void sendResponse(HttpSocket socket, int statusCode, string statusPhrase = null)
{
	try
	{
		auto response = new HttpResponse(socket, false, statusCode, statusPhrase);
		response.send();
	}
	catch (Exception)
	{
		// ignored
	}
}

/// Shorthand for sendResponse
nothrow void sendBadRequest(HttpSocket socket)
{
	socket.sendResponse(HttpStatus.badRequest);
}

/// Shorthand for sendResponse
nothrow void sendNotFound(HttpSocket socket)
{
	socket.sendResponse(HttpStatus.notFound);
}

/// Response from an HTTP server, or a reply to a request from a client.
class HttpResponse : HttpInstance
{
private:
	int statusCode;
	string statusPhrase;

public:
	this(HttpSocket socket, bool hasBody,
		 int statusCode = HttpStatus.ok, string statusPhrase = null, HttpVersion version_ = HttpVersion.v1_1)
	{
		super(socket, hasBody);

		this.statusCode   = statusCode;
		this.statusPhrase = statusPhrase;
		this.version_     = version_;
	}

	override nothrow void clear()
	{
		super.clear();
		statusCode = HttpStatus.none;
		statusPhrase = null;
	}

	void run()
	{
		throw new Exception("Not implemented");
	}

	override string toString() const
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
		if (socket.readln(line) < 1 && line.empty)
		{
			disconnect();
			return false;
		}

		if (line.empty)
		{
			return false;
		}

		auto _httpVersion = to!string(line.byCodeUnit.until!isWhite);
		version_ = _httpVersion.toVersion();

		line = line
		       .byCodeUnit
		       .find!isWhite
		       .source
		       .stripLeft;

		statusCode = parse!int(line);

		line = line.stripLeft;

		statusPhrase = line.idup;

		super.parseHeaders();
		
		debug synchronized
		{
			import std.stdio : stderr;
			stderr.writeln(toString());
		}
		
		return true;
	}
}
