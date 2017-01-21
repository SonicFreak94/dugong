module requestqueue;

import core.thread;

import std.parallelism;
import std.algorithm;
import std.stdio;

import http.request;
import fiberqueue;

private class FiberThread : Thread
{
public:
	this()
	{
		queue = new FiberQueue();
		super(&queue.run);
	}

	FiberQueue queue;
}

/// Handles all HTTP connection requests.
class RequestQueue
{
private:
	size_t threadCount;
	FiberThread[] threads;

public:
	/// Params:
	///	threadCount = Maximum number of worker threads.
	this(size_t threadCount)
	{
		this.threadCount = !threadCount ? totalCPUs : threadCount;
		threads = new FiberThread[this.threadCount];

		foreach (ref t; threads)
		{
			t = new FiberThread();
		}
	}

	/// Counts the number of running threads.
	auto runningThreads()
	{
		return threads.count!(x => x.isRunning);
	}

	/// Adds the specified $(D HttpRequest) to the thread with
	/// the least load.
	/// If all the threads have reached their maximum connection
	/// count, the calling thread will be blocked until space is
	/// available to prevent excessive connections.
	/// Params:
	/// 	r = The request to add.
	void add(HttpRequest r)
	{
		FiberThread t;
		do
		{
			t = threads.minElement!(x => x.queue.count);
			if (t.queue.canAdd)
			{
				break;
			}

			Thread.sleep(10.msecs);
		} while (!t.queue.canAdd);

		t.queue.add(r);
		
		if (!t.isRunning)
		{
			t.start();
		}
	}

	/// Calls $(D Thread.join) on all the threads managed by this instance.
	void join()
	{
		foreach (size_t i, ref t; threads)
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
