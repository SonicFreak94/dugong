import std.conv;
import std.stdio;
import std.string;
import core.time;
import vibe.d;

shared static this()
{
	auto settings = new HTTPServerSettings;
	settings.port = 3128;
	settings.bindAddresses = ["::1", "127.0.0.1"];

	auto router = new URLRouter();
	router.match(HTTPMethod.CONNECT, "*", &handleConnect);
	router.any("*", &passThrough);

	listenHTTP(settings, router);
	logInfo("Proxy started on port 3128.");
}

void handleConnect(HTTPServerRequest req, HTTPServerResponse res)
{
	auto host = req.host.split(":");

	res.headers = req.headers;
	res.statusCode = HTTPStatus.ok;
	res.writeVoidBody();

	auto tcp = connectTCP(host[0], to!ushort(host[1]));
	auto con = res.connectProxy();

	scope (exit)
	{
		tcp.close();
		con.close();
	}
	
	runTask({
		tcp.write(con);
		tcp.close();
	});

	con.write(tcp);
}

void passThrough(HTTPServerRequest req, HTTPServerResponse res)
{
	// don't mind me, just putting functions in functions

	void proxyRequest(scope HTTPClientRequest r)
	{
		r.headers = req.headers;
		r.method = req.method;
		r.bodyWriter.write(req.bodyReader);
	}

	void proxyResponse(scope HTTPClientResponse r)
	{
		auto status = cast(HTTPStatus)r.statusCode;

		with (HTTPStatus) switch (status)
		{
			case movedPermanently:
			case temporaryRedirect:
				res.redirect(r.headers["Location"]);
				break;

			default:
				res.headers = r.headers;
				res.bodyWriter.write(r.bodyReader);
				break;
		}
	}

	try
	{
		requestHTTP(req.requestURL, toDelegate(&proxyRequest), toDelegate(&proxyResponse));
	}
	catch (Exception ex)
	{
		res.writeBody(ex.toString());
		stderr.writeln(ex.msg);
	}
}
