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
	auto listeners = [
		new HttpSocket(AddressFamily.INET, SocketType.STREAM),
		//new HttpSocket(AddressFamily.INET6, SocketType.STREAM)
	];

	listeners.each!(x => x.blocking = false);

	for (ushort i = 0; i <= bindRetry; i++)
	{
		try
		{
			listeners[0].bind(new InternetAddress(proxyPort));
			break;
		}
		catch (Exception ex)
		{
			if (i < bindRetry)
			{
				stderr.writeln(ex.msg);
				stderr.writefln("[IPv4] Retrying... [%d/%d]", i + 1, bindRetry);
				Thread.sleep(1.seconds);
			}
			else
			{
				stderr.writeln(ex.msg);
				stderr.writeln("Aborting.");
				return -1;
			}
		}
	}

/*
	for (ushort i = 0; i <= bindRetry; i++)
	{
		try
		{
			listeners[1].bind(new Internet6Address(cast(ushort)(proxyPort + 1)));
			break;
		}
		catch (Exception ex)
		{
			if (i < bindRetry)
			{
				stderr.writeln(ex.msg);
				stderr.writefln("[IPv6] Retrying... [%d/%d]", i + 1, bindRetry);
				Thread.sleep(1.seconds);
			}
			else
			{
				stderr.writeln(ex.msg);
				stderr.writeln("Aborting.");
				return -1;
			}
		}
	}
*/

	listeners.each!(x => x.listen(1));

	stdout.writeln("Listening on port ", proxyPort);

	auto socketSet = new SocketSet();
	auto queue = new RequestQueue(threadCount);
	size_t count;

	while (listeners.all!(x => x.isAlive))
	{
		try
		{
			listeners.each!(x => socketSet.add(x));
			Socket.select(socketSet, null, null, 1.msecs);

			foreach (l; listeners)
			{
				if (socketSet.isSet(l))
				{
					queue.add(new HttpRequest(l.accept()));
				}
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
	listeners.each!(x => x.disconnect());
	return 0;
}
