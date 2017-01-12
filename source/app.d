import std.conv;
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
			
			// TODO: std.range.zip
			string[string] stupid;
			foreach (f; req.form.toRepresentation())
			{
				stderr.writefln("%s: %s", f.key, f.value);
				stupid[f.key] = f.value;
			}

			// TODO: actually this
			stderr.writeln();
			stderr.writeln("/!\\ Request files: ", req.files);
			stderr.writeln();

			r.writeFormBody(stupid);
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
