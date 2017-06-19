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
import http.common : wait;

/// A concurrent queue of $(D HttpRequest).
class FiberQueue
{
private:
	FiberScheduler fibers;
	const size_t capacity_;
	size_t count_;
	DList!HttpRequest requests;
	Mutex mtx_requests;

public:
	/// Params:
	///		capacity = Number of concurrent connections
	/// allowed in this instance.
	this(size_t capacity = 1000)
	{
		capacity_    = capacity;
		fibers       = new FiberScheduler();
		mtx_requests = new Mutex();
	}

	/// The maximum number of concurrent connections allowed
	/// by this instance.
	@property size_t capacity() const
	{
		return capacity_;
	}

	/// $(D true) if this instance is below maximum capacity.
	@property bool canAdd() const
	{
		synchronized (this) return count_ < capacity;
	}

	/// Number of requests being handled by this instance.
	@property size_t count() const
	{
		synchronized (this) return count_;
	}

	/// Adds $(D HttpRequest) to this instance.
	/// Throws: "Capacity reached" if $(D canAdd) is false.
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

	/// GOTTA GO FAST
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
			while (!mtx_requests.tryLock())
			{
				wait();
			}

			auto search = requests[].find!(x => !x.connected);

			if (!search.empty)
			{
				requests.linearRemove(take(search, 1));
				decrement();
			}

			mtx_requests.unlock();
			wait();
		}
	}
}
