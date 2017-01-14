module http.enums;

enum HttpMethod
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

string toString(HttpMethod method)
{
	with (HttpMethod) switch (method)
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

HttpMethod toMethod(const char[] str)
{
	switch (str)
	{
		case "GET":     return HttpMethod.get;
		case "HEAD":    return HttpMethod.head;
		case "POST":    return HttpMethod.post;
		case "PUT":     return HttpMethod.put;
		case "DELETE":  return HttpMethod.delete_;
		case "TRACE":   return HttpMethod.trace;
		case "OPTIONS": return HttpMethod.options;
		case "CONNECT": return HttpMethod.connect;
		case "PATCH":   return HttpMethod.patch;
		default:        return HttpMethod.none;
	}
}

enum HttpVersion
{
	none,
	v1_0,
	v1_1
}

string toString(HttpVersion version_)
{
	with (HttpVersion) switch (version_)
	{
		case v1_0: return "HTTP/1.0";
		case v1_1: return "HTTP/1.1";
		default:   return null;
	}
}

HttpVersion toVersion(const char[] str)
{
	switch (str)
	{
		case "HTTP/1.0": return HttpVersion.v1_0;
		case "HTTP/1.1": return HttpVersion.v1_1;
		default:         return HttpVersion.none;
	}
}

enum HttpStatus : int
{
	none                          = 0,
	continue_                     = 100,
	switchingProtocols            = 101,
	processing                    = 102,
	ok                            = 200,
	created                       = 201,
	accepted                      = 202,
	nonAuthoritativeInformation   = 203,
	noContent                     = 204,
	resetContent                  = 205,
	partialContent                = 206,
	multiStatus                   = 207,
	alreadyReported               = 208,
	imUsed                        = 226,
	multipleChoices               = 300,
	movedPermanently              = 301,
	found                         = 302,
	seeOther                      = 303,
	notModified                   = 304,
	useProxy                      = 305,
	switchProxy                   = 306,
	temporaryRedirect             = 307,
	permanentRedirect             = 308,
	badRequest                    = 400,
	unauthorized                  = 401,
	paymentRequired               = 402,
	forbidden                     = 403,
	notFound                      = 404,
	methodNotAllowed              = 405,
	notAcceptable                 = 406,
	proxyAuthenticationRequired   = 407,
	requestTimeout                = 408,
	conflict                      = 409,
	gone                          = 410,
	lengthRequired                = 411,
	preconditionFailed            = 412,
	payloadTooLarge               = 413,
	uriTooLong                    = 414,
	unsupportedMediaType          = 415,
	rangeNotSatisfiable           = 416,
	expectationFailed             = 417,
	teapot                        = 418,
	misdirectedRequest            = 421,
	unprocessableEntity           = 422,
	locked                        = 423,
	failedDependency              = 424,
	upgradeRequired               = 426,
	preconditionRequired          = 428,
	tooManyRequests               = 429,
	requestHeaderFieldsTooLarge   = 431,
	unavailableForLegalReasons    = 451,
	internalServerError           = 500,
	notImplemented                = 501,
	badGateway                    = 502,
	serviceUnavailable            = 503,
	gatewayTimeout                = 504,
	httpVersionNotSupported       = 505,
	variantAlsoNegotiates         = 506,
	insufficientStorage           = 507,
	loopDetected                  = 508,
	notExtended                   = 510,
	networkAuthenticationRequired = 511,
}

string toString(HttpStatus status)
{
	with (HttpStatus) switch (status)
	{
		case continue_:                     return "Continue";
		case switchingProtocols:            return "Switching Protocols";
		case processing:                    return "Processing";
		case ok:                            return "OK";
		case created:                       return "Created";
		case accepted:                      return "Accepted";
		case nonAuthoritativeInformation:   return "Non-Authoritative Information";
		case noContent:                     return "No Content";
		case resetContent:                  return "Reset Content";
		case partialContent:                return "Partial Content";
		case multiStatus:                   return "Multi-Status";
		case alreadyReported:               return "Already Reported";
		case imUsed:                        return "IM Used";
		case multipleChoices:               return "Multiple Choices";
		case movedPermanently:              return "Moved Permanently";
		case found:                         return "Found";
		case seeOther:                      return "See Other";
		case notModified:                   return "Not Modified";
		case useProxy:                      return "Use Proxy";
		case switchProxy:                   return "Switch Proxy";
		case temporaryRedirect:             return "Temporary Redirect";
		case permanentRedirect:             return "Permanent Redirect";
		case badRequest:                    return "Bad Request";
		case unauthorized:                  return "Unauthorized";
		case paymentRequired:               return "Payment Required";
		case forbidden:                     return "Forbidden";
		case notFound:                      return "Not Found";
		case methodNotAllowed:              return "Method Not Allowed";
		case notAcceptable:                 return "Not Acceptable";
		case proxyAuthenticationRequired:   return "Proxy Authentication Required";
		case requestTimeout:                return "Request Time-out";
		case conflict:                      return "Conflict";
		case gone:                          return "Gone";
		case lengthRequired:                return "Length Required";
		case preconditionFailed:            return "Precondition Failed";
		case payloadTooLarge:               return "Payload Too Large";
		case uriTooLong:                    return "URI Too Long";
		case unsupportedMediaType:          return "Unsupported Media Type";
		case rangeNotSatisfiable:           return "Range Not Satisfiable";
		case expectationFailed:             return "Expectation Failed";
		case teapot:                        return "I'm a teapot";
		case misdirectedRequest:            return "Misdirected Request";
		case unprocessableEntity:           return "Unprocessable Entity";
		case locked:                        return "Locked";
		case failedDependency:              return "Failed Dependency";
		case upgradeRequired:               return "Upgrade Required";
		case preconditionRequired:          return "Precondition Required";
		case tooManyRequests:               return "Too Many Requests";
		case requestHeaderFieldsTooLarge:   return "Request Header Fields Too Large";
		case unavailableForLegalReasons:    return "Unavailable For Legal Reasons";
		case internalServerError:           return "Internal Server Error";
		case notImplemented:                return "Not Implemented";
		case badGateway:                    return "Bad Gateway";
		case serviceUnavailable:            return "Service Unavailable";
		case gatewayTimeout:                return "Gateway Time-out";
		case httpVersionNotSupported:       return "HTTP Version Not Supported";
		case variantAlsoNegotiates:         return "Variant Also Negotiates";
		case insufficientStorage:           return "Insufficient Storage";
		case loopDetected:                  return "Loop Detected";
		case notExtended:                   return "Not Extended";
		case networkAuthenticationRequired: return "Network Authentication Required";
		default:                            return null;
	}
}

HttpStatus toStatus(const char[] str)
{
	switch (str)
	{
		case "Continue":                        return HttpStatus.continue_;
		case "Switching Protocols":             return HttpStatus.switchingProtocols;
		case "Processing":                      return HttpStatus.processing;
		case "OK":                              return HttpStatus.ok;
		case "Created":                         return HttpStatus.created;
		case "Accepted":                        return HttpStatus.accepted;
		case "Non-Authoritative Information":   return HttpStatus.nonAuthoritativeInformation;
		case "No Content":                      return HttpStatus.noContent;
		case "Reset Content":                   return HttpStatus.resetContent;
		case "Partial Content":                 return HttpStatus.partialContent;
		case "Multi-Status":                    return HttpStatus.multiStatus;
		case "Already Reported":                return HttpStatus.alreadyReported;
		case "IM Used":                         return HttpStatus.imUsed;
		case "Multiple Choices":                return HttpStatus.multipleChoices;
		case "Moved Permanently":               return HttpStatus.movedPermanently;
		case "Found":                           return HttpStatus.found;
		case "See Other":                       return HttpStatus.seeOther;
		case "Not Modified":                    return HttpStatus.notModified;
		case "Use Proxy":                       return HttpStatus.useProxy;
		case "Switch Proxy":                    return HttpStatus.switchProxy;
		case "Temporary Redirect":              return HttpStatus.temporaryRedirect;
		case "Permanent Redirect":              return HttpStatus.permanentRedirect;
		case "Bad Request":                     return HttpStatus.badRequest;
		case "Unauthorized":                    return HttpStatus.unauthorized;
		case "Payment Required":                return HttpStatus.paymentRequired;
		case "Forbidden":                       return HttpStatus.forbidden;
		case "Not Found":                       return HttpStatus.notFound;
		case "Method Not Allowed":              return HttpStatus.methodNotAllowed;
		case "Not Acceptable":                  return HttpStatus.notAcceptable;
		case "Proxy Authentication Required":   return HttpStatus.proxyAuthenticationRequired;
		case "Request Time-out":                return HttpStatus.requestTimeout;
		case "Conflict":                        return HttpStatus.conflict;
		case "Gone":                            return HttpStatus.gone;
		case "Length Required":                 return HttpStatus.lengthRequired;
		case "Precondition Failed":             return HttpStatus.preconditionFailed;
		case "Payload Too Large":               return HttpStatus.payloadTooLarge;
		case "URI Too Long":                    return HttpStatus.uriTooLong;
		case "Unsupported Media Type":          return HttpStatus.unsupportedMediaType;
		case "Range Not Satisfiable":           return HttpStatus.rangeNotSatisfiable;
		case "Expectation Failed":              return HttpStatus.expectationFailed;
		case "I'm a teapot":                    return HttpStatus.teapot;
		case "Misdirected Request":             return HttpStatus.misdirectedRequest;
		case "Unprocessable Entity":            return HttpStatus.unprocessableEntity;
		case "Locked":                          return HttpStatus.locked;
		case "Failed Dependency":               return HttpStatus.failedDependency;
		case "Upgrade Required":                return HttpStatus.upgradeRequired;
		case "Precondition Required":           return HttpStatus.preconditionRequired;
		case "Too Many Requests":               return HttpStatus.tooManyRequests;
		case "Request Header Fields Too Large": return HttpStatus.requestHeaderFieldsTooLarge;
		case "Unavailable For Legal Reasons":   return HttpStatus.unavailableForLegalReasons;
		case "Internal Server Error":           return HttpStatus.internalServerError;
		case "Not Implemented":                 return HttpStatus.notImplemented;
		case "Bad Gateway":                     return HttpStatus.badGateway;
		case "Service Unavailable":             return HttpStatus.serviceUnavailable;
		case "Gateway Time-out":                return HttpStatus.gatewayTimeout;
		case "HTTP Version Not Supported":      return HttpStatus.httpVersionNotSupported;
		case "Variant Also Negotiates":         return HttpStatus.variantAlsoNegotiates;
		case "Insufficient Storage":            return HttpStatus.insufficientStorage;
		case "Loop Detected":                   return HttpStatus.loopDetected;
		case "Not Extended":                    return HttpStatus.notExtended;
		case "Network Authentication Required": return HttpStatus.networkAuthenticationRequired;
		default:                                return HttpStatus.none;
	}
}
