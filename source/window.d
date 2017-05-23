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

	@safe @property
	{
		nothrow auto target() const
		{
			return _target;
		}

		nothrow auto length() const
		{
			return buffer.data.length;
		}

		nothrow bool reachedTarget() const
		{
			return length == target;
		}
	}

	@safe nothrow void put(T value, ref Appender!(T[]) overflow)
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

	@safe @nogc nothrow bool match(in T[] data)
	{
		return reachedTarget && buffer.data == data;
	}
}
