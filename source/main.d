import std.stdio;
import std.socket;
import std.parallelism;

import http;

ushort proxyPort = 3128;

int main(string[] argv)
{
	auto listener = new TcpSocket();
	listener.bind(new InternetAddress(proxyPort));
	listener.listen(1);

	HttpInstance[] instances;

	auto socketSet = new SocketSet();

	while (listener.isAlive)
	{
		try
		{
			socketSet.add(listener);
			Socket.select(socketSet, null, null);

			if (socketSet.isSet(listener))
			{
				stdout.writeln(__FUNCTION__, ": accepting");
				instances ~= new HttpRequest(listener.accept());
				stdout.writeln(__FUNCTION__, ": instances: ", instances.length);
			}

			stdout.writeln(__FUNCTION__, ": running");

			foreach (instance; taskPool.parallel(instances, 1))
			//foreach (instance; instances)
			{
				instance.run();
			}

			stdout.writeln(__FUNCTION__, ": done");

			import std.algorithm;
			import std.array;
			instances = instances.filter!(x => x.connected()).array;
			stdout.writeln(__FUNCTION__, ": instances: ", instances.length);
		}
		catch (Exception ex)
		{
			stderr.writeln(ex.msg);
		}
	}

	listener.disconnect();
	return 0;
}
