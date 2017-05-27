module buffer;

import std.algorithm;
import std.container.array;
import std.exception;

class Buffer(T, size_t InitLength = 1024, size_t WindowSize = 1)
	if (is(T : ubyte) || is(T : byte) || is(T : char))
{
private:
	import core.stdc.stdlib : malloc, realloc, free;

	T* _buffer;
	size_t _length;

	size_t _avg_c;
	size_t _avg_i;
	size_t[WindowSize] _avg_p;

public:
	this()
	{
		length = InitLength;
	}
	~this()
	{
		clear();
	}

	@property
	{
		nothrow bool empty() const
		{
			return !length || _buffer is null;
		}

		nothrow size_t length() const
		{
			return _length;
		}

		void length(size_t newLength)
		{
			if (!newLength)
			{
				clear();
				return;
			}

			if (_buffer is null)
			{
				_buffer = cast(T*)malloc(newLength);
			}
			else
			{
				// TODO: fake it if we're going smaller!
				_buffer = cast(T*)realloc(_buffer, newLength);
			}

			enforce(_buffer !is null, "malloc failed");
			_length = newLength;
		}

		nothrow size_t opDollar() const
		{
			return length;
		}
	}

	auto opSlice()
	{
		if (_buffer is null)
		{
			return null;
		}

		return _buffer[0 .. length];
	}

	auto opSlice(size_t i, size_t j)
	{
		enforce(i >= 0 && i < length && j >= 0 && j <= length);
		return _buffer[i .. j];
	}

	nothrow void clear()
	{
		_avg_i = 0;
		_avg_c = 0;
		
		if (_buffer !is null)
		{
			free(_buffer);
			_buffer = null;
		}

		_length = 0;
	}

	void reset()
	{
		clear();
		length = InitLength;
	}

	void addLength(size_t newLength)
	{
		_avg_p[_avg_i++] = newLength;
		_avg_i %= WindowSize;

		if (_avg_c < WindowSize)
		{
			++_avg_c;
			return;
		}

		auto s = sum(_avg_p[]) / WindowSize;

		if (s >= newLength && s >= length)
		{
			synchronized debug
			{
				import std.stdio : stderr;
				auto _len = length;
				stderr.writefln("EXPANDING: %d -> %d", _len, _len * 2);
			}

			length = length * 2;
		}

		_avg_i = 0;
		_avg_c = 0;
	}
}
