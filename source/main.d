module main;

import core.thread;
import core.time;

import std.algorithm;
import std.array;
import std.socket;
import std.stdio;

import http;
import threadqueue;

ushort proxyPort = 3128;

int main(string[] argv)
{
	Socket listener = new TcpSocket();
	listener.bind(new InternetAddress(proxyPort));
	listener.blocking = false;
	listener.listen(1);

	auto socketSet = new SocketSet();
	debug auto queue = new ThreadQueue(1000); // lol
	else  auto queue = new ThreadQueue();

	while (listener.isAlive)
	{
		try
		{
			socketSet.add(listener);
			Socket.select(socketSet, null, null, 1.msecs);

			if (socketSet.isSet(listener))
			{
				auto instance = new HttpRequest(listener.accept());
				queue.add(new Thread(&instance.run));
			}
		}
		catch (Exception ex)
		{
			stderr.writeln(ex.msg);
		}

		queue.run();
		Thread.sleep(1.msecs);
	}

	listener.disconnect();
	return 0;
}
