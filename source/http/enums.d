module http.enums;

/// Defines supported HTTP request methods.
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
	switch (method) with (HttpMethod)
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

/// Converts from $(D string) to $(D HttpMethod).
HttpMethod toMethod(const char[] str)
{
	switch (str) with (HttpMethod)
	{
		case "GET":     return get;
		case "HEAD":    return head;
		case "POST":    return post;
		case "PUT":     return put;
		case "DELETE":  return delete_;
		case "TRACE":   return trace;
		case "OPTIONS": return options;
		case "CONNECT": return connect;
		case "PATCH":   return patch;
		default:        return none;
	}
}

/// Defines supported HTTP protocol versions.
enum HttpVersion
{
	none,
	v1_0,
	v1_1
}

string toString(HttpVersion version_)
{
	switch (version_) with (HttpVersion)
	{
		case v1_0: return "HTTP/1.0";
		case v1_1: return "HTTP/1.1";
		default:   return null;
	}
}

/// Converts $(D string) to $(D HttpVersion).
HttpVersion toVersion(const char[] str)
{
	switch (str) with (HttpVersion)
	{
		case "HTTP/1.0": return v1_0;
		case "HTTP/1.1": return v1_1;
		default:         return none;
	}
}

/// Defines common HTTP status codes.
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
	switch (status) with (HttpStatus)
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

/// Converts from common status phrases to $(D HttpStatus).
HttpStatus toStatus(const char[] str)
{
	switch (str) with (HttpStatus)
	{
		case "Continue":                        return continue_;
		case "Switching Protocols":             return switchingProtocols;
		case "Processing":                      return processing;
		case "OK":                              return ok;
		case "Created":                         return created;
		case "Accepted":                        return accepted;
		case "Non-Authoritative Information":   return nonAuthoritativeInformation;
		case "No Content":                      return noContent;
		case "Reset Content":                   return resetContent;
		case "Partial Content":                 return partialContent;
		case "Multi-Status":                    return multiStatus;
		case "Already Reported":                return alreadyReported;
		case "IM Used":                         return imUsed;
		case "Multiple Choices":                return multipleChoices;
		case "Moved Permanently":               return movedPermanently;
		case "Found":                           return found;
		case "See Other":                       return seeOther;
		case "Not Modified":                    return notModified;
		case "Use Proxy":                       return useProxy;
		case "Switch Proxy":                    return switchProxy;
		case "Temporary Redirect":              return temporaryRedirect;
		case "Permanent Redirect":              return permanentRedirect;
		case "Bad Request":                     return badRequest;
		case "Unauthorized":                    return unauthorized;
		case "Payment Required":                return paymentRequired;
		case "Forbidden":                       return forbidden;
		case "Not Found":                       return notFound;
		case "Method Not Allowed":              return methodNotAllowed;
		case "Not Acceptable":                  return notAcceptable;
		case "Proxy Authentication Required":   return proxyAuthenticationRequired;
		case "Request Time-out":                return requestTimeout;
		case "Conflict":                        return conflict;
		case "Gone":                            return gone;
		case "Length Required":                 return lengthRequired;
		case "Precondition Failed":             return preconditionFailed;
		case "Payload Too Large":               return payloadTooLarge;
		case "URI Too Long":                    return uriTooLong;
		case "Unsupported Media Type":          return unsupportedMediaType;
		case "Range Not Satisfiable":           return rangeNotSatisfiable;
		case "Expectation Failed":              return expectationFailed;
		case "I'm a teapot":                    return teapot;
		case "Misdirected Request":             return misdirectedRequest;
		case "Unprocessable Entity":            return unprocessableEntity;
		case "Locked":                          return locked;
		case "Failed Dependency":               return failedDependency;
		case "Upgrade Required":                return upgradeRequired;
		case "Precondition Required":           return preconditionRequired;
		case "Too Many Requests":               return tooManyRequests;
		case "Request Header Fields Too Large": return requestHeaderFieldsTooLarge;
		case "Unavailable For Legal Reasons":   return unavailableForLegalReasons;
		case "Internal Server Error":           return internalServerError;
		case "Not Implemented":                 return notImplemented;
		case "Bad Gateway":                     return badGateway;
		case "Service Unavailable":             return serviceUnavailable;
		case "Gateway Time-out":                return gatewayTimeout;
		case "HTTP Version Not Supported":      return httpVersionNotSupported;
		case "Variant Also Negotiates":         return variantAlsoNegotiates;
		case "Insufficient Storage":            return insufficientStorage;
		case "Loop Detected":                   return loopDetected;
		case "Not Extended":                    return notExtended;
		case "Network Authentication Required": return networkAuthenticationRequired;
		default:                                return none;
	}
}
