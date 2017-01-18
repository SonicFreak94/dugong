module requestqueue;

import core.thread;

import std.container;
import std.parallelism;
import std.stdio;

import http.request;
import fiberqueue;

// TODO: concurrency per thread

class FiberThread : Thread
{
public:
	this()
	{
		queue = new FiberQueue();
		super(&queue.run);
	}

	FiberQueue queue;
}

class RequestQueue
{
private:
	size_t threadCount;
	DList!HttpRequest requests;
	FiberThread[] threads;
	size_t instances;

public:
	this(size_t threadCount = totalCPUs)
	{
		this.threadCount = threadCount;
		threads = new FiberThread[threadCount];
	}

	void add(HttpRequest r)
	{
		requests.insertBack(r);
	}

	void join()
	{
		foreach (size_t i, ref FiberThread t; threads)
		{
			if (t is null)
			{
				continue;
			}

			join(i, t);
		}
	}

	void run()
	{
		foreach (size_t i, ref FiberThread t; threads)
		{
			if (!t.isRunning)
			{
				join(i, t);
			}

			if (requests.empty)
			{
				continue;
			}

			if (t is null)
			{
				t = new FiberThread();
				increment();
			}

			with (t)
			{
				if (queue.canAdd)
				{
					queue.add(popRequest());
				}

				if (!isRunning)
				{
					start();
				}
			}
		}
	}

private:
	auto popRequest()
	{
		auto r = requests.front;
		requests.removeFront();
		return r;
	}

	private void join(size_t i, ref FiberThread t)
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
		decrement();
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
