module threadqueue;

import core.thread;

import std.container;
import std.parallelism;
import std.stdio;

// TODO: maybe array of fiber sheduler for maximum saturation?

class ThreadQueue
{
private:
	size_t threadCount;
	DList!Thread queue;
	Thread[] running;

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
		foreach (ref Thread t; running)
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
					stderr.writeln(ex.msg);
				}

				t = null;
			}

			if (queue.empty)
			{
				continue;
			}

			t = queue.front();
			queue.removeFront();
			t.start();
		}
	}
}
