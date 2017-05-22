module window;

import std.array;

struct SearchWindow(T)
{
private:
	size_t _target;
	Appender!(T[]) buffer;

public:
	this(size_t target)
	{
		_target = target;
	}

	~this()
	{
		buffer.clear();
	}

	@property auto target()
	{
		return _target;
	}

	@property auto length()
	{
		return buffer.data.length;
	}

	@property bool reachedTarget()
	{
		return length == target;
	}

	void put(T value, ref Appender!(T[]) overflow)
	{
		if (length < target)
		{
			buffer.put(value);
		}
		else
		{
			overflow.put(buffer.data[0]);

			auto trimmed = buffer.data[1 .. $].dup;
			buffer.clear();
			buffer.put(trimmed);
			buffer.put(value);
		}
	}

	bool match(in T[] data)
	{
		return reachedTarget && buffer.data == data;
	}
}
