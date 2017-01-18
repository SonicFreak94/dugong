module requestqueue;

import core.thread;

import std.parallelism;
import std.algorithm;
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
	FiberThread[] threads;

public:
	this(size_t threadCount = totalCPUs)
	{
		this.threadCount = threadCount;
		threads = new FiberThread[threadCount];

		foreach (ref t; threads)
		{
			t = new FiberThread();
		}
	}

	@property auto runningThreads()
	{
		return threads.count!(x => x.isRunning);
	}

	void add(HttpRequest r)
	{
		// dirty load balancing hack
		auto t = threads.minElement!(x => x.queue.count);

		t.queue.add(r);
		
		if (!t.isRunning)
		{
			t.start();
		}
	}

	void join()
	{
		foreach (size_t i, ref FiberThread t; threads)
		{
			join(i, t);
		}
	}

private:
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
	}
}
