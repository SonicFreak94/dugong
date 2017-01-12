import std.stdio;
import std.socket;
import std.conv;
import std.string;

import http.server;

ushort proxyPort = 3128;

int main(string[] argv)
{
	auto listener = new TcpSocket();
	listener.blocking = false;
	listener.bind(new InternetAddress(proxyPort));
	listener.listen(1);

	auto socketSet = new SocketSet();

	while (listener.isAlive)
	{
		try
		{
			socketSet.add(listener);
			Socket.select(socketSet, null, null);

			if (socketSet.isSet(listener))
			{
				auto socket = listener.accept();
				auto req = new ServerRequest(socket);
				req.run();
				listener.disconnect();
			}
		}
		catch (Exception ex)
		{
			stderr.writeln(ex.msg);
			stderr.writeln("(press any key)");
			stdin.readln();
		}
	}

	listener.disconnect();
	return 0;
}
