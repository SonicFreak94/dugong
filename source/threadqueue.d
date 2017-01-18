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

	void join()
	{
		foreach (i, ref Thread t; running)
		{
			if (t is null)
			{
				continue;
			}

			join(i, t);
			decrement();
		}
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

				join(i, t);
				decrement();
			}

			if (queue.empty)
			{
				continue;
			}

			t = queue.front();
			queue.removeFront();
			t.start();

			increment();
		}
	}

private:
	private void join(size_t i, ref Thread t)
	{
		if (t is null)
		{
			return;
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
	}

	private void increment()
	{
		stderr.writeln("threads: ", ++instances);
	}

	private void decrement()
	{
		stderr.writeln("threads: ", --instances);
	}
}
