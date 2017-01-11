import std.stdio;
import vibe.d;

shared static this()
{
	auto settings = new HTTPServerSettings;
	settings.port = 3128;
	settings.bindAddresses = ["::1", "127.0.0.1"];
	listenHTTP(settings, &passThrough);

	logInfo("Proxy started on port 3128.");
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
		if (req.method == HTTPMethod.CONNECT)
		{
			auto url = URL.parse("http://" ~ req.host ~ "/");
			logInfo("IDK WHAT TO DO BUT HERE TAKE THIS: %s:%u", url.host, url.port);
			return;
		}

		requestHTTP(req.requestURL, toDelegate(&proxyRequest), toDelegate(&proxyResponse));
	}
	catch (Exception ex)
	{
		res.writeBody(ex.toString());
		stderr.writeln(ex.msg);
	}
}
