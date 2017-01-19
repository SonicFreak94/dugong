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

/// Convenience function which constructs $(D HttpResponse) with
/// the given status code and immediately sends it.
nothrow void sendResponse(ref Socket socket, int statusCode, string statusPhrase = null)
{
	try
	{
		auto request = new HttpResponse(socket, statusCode, statusPhrase);
		request.send();
	}
	catch (Exception)
	{
		// ignored
	}
}

/// Shorthand for sendResponse
nothrow void sendBadRequest(ref Socket socket)
{
	socket.sendResponse(HttpStatus.badRequest);
}

/// Shorthand for sendResponse
nothrow void sendNotFound(ref Socket socket)
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
	/// same as the other constructor but with a dirty hack
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
		
		debug synchronized
		{
			import std.stdio : stderr;
			stderr.writeln(toString());
		}
		
		return true;
	}
}
