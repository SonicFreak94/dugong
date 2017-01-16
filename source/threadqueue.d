module threadqueue;

import core.thread;

import std.container;
import std.parallelism;
import std.stdio;

// TODO: concurrency per thread

class ThreadQueue
{
private:
	size_t threadCount;
	DList!Thread queue;
	Thread[] running;
	size_t instances;

public:
	this(size_t threadCount = totalCPUs)
	{
		this.threadCount = threadCount;
		running = new Thread[threadCount];
	}

	void add(Thread t)
	{
		queue.insertBack(t);
	}

	void run()
	{
		foreach (i, ref Thread t; running)
		{
			if (t !is null)
			{
				if (t.isRunning)
				{
					continue;
				}

				try
				{
					// Re-throw any available exceptions
					t.join(true);
				}
				catch (Exception ex)
				{
					stderr.writefln("[%d] %s", i, ex.msg);
				}

				t = null;
				stderr.writeln("threads: ", --instances);
			}

			if (queue.empty)
			{
				continue;
			}

			t = queue.front();
			queue.removeFront();
			t.start();

			stderr.writeln("threads: ", ++instances);
		}
	}
}
