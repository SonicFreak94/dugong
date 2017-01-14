module http.response;

import core.time;
import std.algorithm;
import std.array;
import std.conv;
import std.exception;

import http.common;
import http.enums;

// TODO: cookies?

class HttpResponse : HttpInstance
{
public:
	string[string] headers;
	HttpVersion version_ = HttpVersion.v1_1;
	int statusCode       = HttpStatus.ok;
	ubyte[] body_;

	this(Socket socket)
	{
		super(socket);
	}

	override void run()
	{
		throw new Exception("Not implemented");
	}

	override void send()
	{
		auto str = toString();
		socket.send(cast(ubyte[])str ~ body_);
	}

	override string toString()
	{
		Appender!string result;

		result.writeln(version_.toString(),
					   ' ', to!string(statusCode),
					   ' ', (cast(HttpStatus)statusCode).toString(),
					);

		if (headers.length)
		{
			headers.byKeyValue.each!(x => result.writeln(x.key ~ ": " ~ x.value));
		}

		result.writeln();
		return result.data;
	}
}
