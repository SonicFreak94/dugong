module main;

import core.thread;
import core.time;

import std.algorithm;
import std.array;
import std.getopt;
import std.socket;
import std.stdio;

import http;
import requestqueue;

/// Number of bind retries before giving up.
ushort bindRetry = 100;
/// The port to listen on for connections.
ushort proxyPort = 3128;
/// Number of allowed worker threads.
size_t threadCount;

int main(string[] argv)
{
	try
	{
		auto opt = getopt(argv,
			"p|port", "The port to listen on for connections.", &proxyPort,
			"t|threads", "Maximum number of worker threads.", &threadCount);

		if (opt.helpWanted)
		{
			defaultGetoptPrinter("dugong [options]", opt.options);
			return 0;
		}
	}
	catch (Exception ex)
	{
		stdout.writeln(ex.msg);
		return -1;
	}

	stdout.writeln("Started. Opening socket...");

	Socket listener = new TcpSocket();

	for (ushort i = 0; i < bindRetry; i++)
	{
		try
		{
			listener.bind(new InternetAddress(proxyPort));
			break;
		}
		catch (Exception ex)
		{
			stderr.writeln(ex.msg);
			stderr.writeln("Retrying...");
			Thread.sleep(1.seconds);
		}
	}
	
	listener.blocking = false;
	listener.listen(1);

	stdout.writeln("Listening on port ", proxyPort);

	auto socketSet = new SocketSet();
	auto queue = new RequestQueue(threadCount);
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

		auto current = queue.runningThreads();
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
