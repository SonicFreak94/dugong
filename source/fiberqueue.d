module fiberqueue;

public import std.concurrency;

import core.thread;
import core.sync.mutex;

import std.range;
import std.container.dlist;
import std.algorithm;
import std.array;
import std.exception;

import http.request;

pragma(inline) void wait()
{
	Thread.sleep(1.msecs);
	yield();
}

class FiberQueue
{
private:
	FiberScheduler fibers;
	const size_t capacity_;
	size_t count_;
	DList!HttpRequest requests;
	Mutex mtx_requests;

public:
	this(size_t capacity = 1000)
	{
		this.capacity_ = capacity;
		fibers        = new FiberScheduler();
		mtx_requests  = new Mutex();
	}

	@property size_t capacity() { return capacity_; }

	@property bool canAdd()
	{
		synchronized (this) return count_ < capacity;
	}

	@property size_t count() { synchronized (this) return count_; }

	void add(HttpRequest r)
	{
		enforce(canAdd, "Capacity reached");

		synchronized (mtx_requests)
		{
			requests.insertBack(r);
			fibers.spawn(&r.run);
			increment();
		}
	}

	void run()
	{
		fibers.start(&prune);
	}

private:
	void increment()
	{
		synchronized (this) ++count_;
	}
	void decrement()
	{
		synchronized (this) --count_;
	}
	@property bool empty()
	{
		synchronized (this) return !count_;
	}

	void prune()
	{
		while (empty)
		{
			wait();
		}

		while (!empty)
		{
			synchronized (mtx_requests)
			{
				auto search = requests[].find!(x => !x.connected);

				if (!search.empty)
				{
					requests.linearRemove(take(search, 1));
					decrement();
				}
			}

			wait();
		}
	}
}
