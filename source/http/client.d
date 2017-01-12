module http.client;
public import http.common;

class ClientRequest : Request
{
public:
	this(Socket socket)
	{
		super(socket);
	}
}

class ClientResponse : Response
{

}
