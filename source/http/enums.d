module http.enums;

enum Method
{
	none,
	get,
	head,
	post,
	put,
	delete_,
	trace,
	options,
	connect,
	patch
}

string toString(Method method)
{
	with (Method) switch (method)
	{
		case get:     return "GET";
		case head:    return "HEAD";
		case post:    return "POST";
		case put:     return "PUT";
		case delete_: return "DELETE";
		case trace:   return "TRACE";
		case options: return "OPTIONS";
		case connect: return "CONNECT";
		case patch:   return "PATCH";
		default:      return null;
	}
}

Method toMethod(const char[] str)
{
	switch (str)
	{
		case "GET":     return Method.get;
		case "HEAD":    return Method.head;
		case "POST":    return Method.post;
		case "PUT":     return Method.put;
		case "DELETE":  return Method.delete_;
		case "TRACE":   return Method.trace;
		case "OPTIONS": return Method.options;
		case "CONNECT": return Method.connect;
		case "PATCH":   return Method.patch;
		default:        return Method.none;
	}
}

enum Version
{
	none,
	v1_0,
	v1_1
}

string toString(Version version_)
{
	with (Version) switch (version_)
	{
		case v1_0: return "HTTP/1.0";
		case v1_1: return "HTTP/1.1";
		default:   return null;
	}
}

Version toVersion(const char[] str)
{
	switch (str)
	{
		case "HTTP/1.0": return Version.v1_0;
		case "HTTP/1.1": return Version.v1_1;
		default:         return Version.none;
	}
}
