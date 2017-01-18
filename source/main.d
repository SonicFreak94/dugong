module main;

import core.thread;
import core.time;

import std.algorithm;
import std.array;
import std.socket;
import std.stdio;

import http;
import requestqueue;

ushort proxyPort = 3128;

int main(string[] argv)
{
	Socket listener = new TcpSocket();
	listener.bind(new InternetAddress(proxyPort));
	listener.blocking = false;
	listener.listen(1);

	auto socketSet = new SocketSet();
	auto queue = new RequestQueue();

	while (listener.isAlive)
	{
		try
		{
			socketSet.add(listener);
			Socket.select(socketSet, null, null, 1.msecs);

			if (socketSet.isSet(listener))
			{
				queue.add(new HttpRequest(listener.accept()));
			}
		}
		catch (Exception ex)
		{
			stderr.writeln(ex.msg);
		}

		queue.run();
		Thread.sleep(1.msecs);
	}

	queue.join();
	listener.disconnect();
	return 0;
}
