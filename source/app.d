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
	logInfo(req.toString());

	// TODO: CONNECT method

	requestHTTP(req.requestURL,
		(scope HTTPClientRequest r)
		{
			r.headers = req.headers;
			r.method = req.method;
			r.bodyWriter.write(req.bodyReader);
			logInfo(r.toString());
		},		
		(scope HTTPClientResponse r)
		{
			auto status = cast(HTTPStatus)r.statusCode;

			if (isSuccessCode(status))
			{
				res.headers = r.headers;
				res.bodyWriter.write(r.bodyReader);
			}
			else
			{
				with (HTTPStatus) switch (status)
				{
					case movedPermanently:
					case temporaryRedirect:
						res.redirect(r.headers["Location"]);
						break;

					default:
						throw new Exception("Unhandled error code " ~ httpStatusText(status));
				}
			}

			logInfo(res.toString());			
		}
	);
}
