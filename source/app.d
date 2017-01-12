import std.algorithm;
import std.conv;
import std.range;
import std.stdio;
import std.string;
import vibe.d;

shared static this()
{
	auto settings = new HTTPServerSettings;
	settings.port = 3128;
	settings.bindAddresses = ["::1", "127.0.0.1"];
	settings.options = HTTPServerOption.defaults;

	auto router = new URLRouter();
	router.match(HTTPMethod.CONNECT, "*", &handleConnect);
	router.any("*", &handleAny);

	listenHTTP(settings, router);
	logInfo("Proxy started on port 3128.");
}

void handleConnect(HTTPServerRequest req, HTTPServerResponse res)
{
	stderr.writeln(req.toString());
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

void handleAny(HTTPServerRequest req, HTTPServerResponse res)
{
	stderr.writeln(req.toString());
	// don't mind me, just putting functions in functions

	void proxyRequest(scope HTTPClientRequest r)
	{
		r.headers = req.headers;
		r.method  = req.method;

		if (r.method == HTTPMethod.POST)
		{
			stderr.writeln("/!\\ Request form: ");
			
			auto form = req.form.toRepresentation();
			auto header = zip(form.map!(x => x.key), form.map!(x => x.value));

			// TODO: files
			// auto files = req.files.toRepresentation();
			// problem:
			// https://github.com/rejectedsoftware/vibe.d/blob/b86e5e0eb9e5784fcc73888fc858e7609d01f028/http/vibe/http/client.d#L736

			stderr.writeln(header);
			r.writeFormBody(header);
		}

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
				stderr.writeln("Response code: ", to!string(status));
				res.cookies = r.cookies;
				res.headers = r.headers;
				res.statusCode = r.statusCode;
				res.statusPhrase = r.statusPhrase;

				res.bodyWriter.write(r.bodyReader);
				break;
		}
	}

	requestHTTP(req.requestURL, toDelegate(&proxyRequest), toDelegate(&proxyResponse));
}
