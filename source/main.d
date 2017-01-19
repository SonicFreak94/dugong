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
	stdout.writeln("Started. Opening socket...");

	Socket listener = new TcpSocket();
	listener.bind(new InternetAddress(proxyPort));
	listener.blocking = false;
	listener.listen(1);

	stdout.writeln("Listening on port ", proxyPort);

	auto socketSet = new SocketSet();
	/*debug auto queue = new RequestQueue(1);
	else  */auto queue = new RequestQueue();
	size_t count;

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

		auto current = queue.runningThreads;
		if (current != count)
		{
			stdout.writeln("threads: ", current);
			count = current;
		}

		Thread.sleep(1.msecs);
	}

	queue.join();
	listener.disconnect();
	return 0;
}
