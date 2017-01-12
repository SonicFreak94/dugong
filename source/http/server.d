module http.server;
public import http.common;

class ServerRequest : Request
{
public:
	this(Socket socket)
	{
		super(socket);
	}
}

class ServerResponse : Response
{

}
