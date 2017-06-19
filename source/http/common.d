module http.common;

public import std.socket;

import core.thread;
import core.time;

import std.array;
import std.concurrency;
import std.exception;

/// Represents an HTTP EOL
const enum HTTP_BREAK = "\r\n";
/// Receive buffer size (1MiB)
const enum HTTP_BUFFLEN = 1 * 1024 * 1024;

/// Yields and then sleeps the current thread.
nothrow void wait()
{
	yield();
	Thread.sleep(1.msecs);
}

/**
	Calls `Socket.shutdown` with the parameter `SocketShutdown.BOTH` on the specified
	socket and closes the socket.

	Params:
		socket = The socket to disconnect.
*/
@safe nothrow void disconnect(scope Socket socket)
{
	if (socket !is null)
	{
		socket.shutdown(SocketShutdown.BOTH);
		socket.close();
	}
}

/**
	Pseudo-blocking version of `Socket.receive` for non-blocking
	sockets which calls `yield` until data has been received or
	the connection is terminated.

	Params:
		socket = The socket to read from.
		buffer = Output buffer to store the received data.

	Returns:
		The number of bytes read, `0` if the connection has been closed,
		or `Socket.ERROR` on failure.
*/
ptrdiff_t receiveAsync(scope Socket socket, scope void[] buffer)
{
	if (socket is null || !socket.isAlive)
	{
		return 0;
	}

	ptrdiff_t length = -1;
	const start = MonoTime.currTime;
	Duration timeout;

	socket.getOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, timeout);
	enforce(timeout >= 1.msecs, "SocketOption.RCVTIMEO must be at least 1ms");

	do
	{
		length = socket.receive(buffer);

		if (!length || length == Socket.ERROR)
		{
			if (!wouldHaveBlocked())
			{
				return 0;
			}

			yield();
		}
	} while (length < 1 && MonoTime.currTime - start < timeout);

	return length;
}

/**
	Pseudo-blocking version of `Socket.send` for non-blocking
	sockets which calls `yield` until data has been sent or
	the connection is terminated.

	Params:
		socket = The socket to write to.
		buffer = The buffer to write to the socket.

	Returns:
		The number of bytes read, `0` if the connection has been closed,
		or `Socket.ERROR` on failure.
*/
ptrdiff_t sendAsync(scope Socket socket, scope const(void)[] buffer)
{
	if (socket is null || !socket.isAlive)
	{
		return 0;
	}

	ptrdiff_t result, sent;
	auto start = MonoTime.currTime;
	Duration timeout;

	socket.getOption(SocketOptionLevel.SOCKET, SocketOption.SNDTIMEO, timeout);

	do
	{
		sent = socket.send(buffer[result .. $]);

		if (!sent || sent == Socket.ERROR)
		{
			if (!wouldHaveBlocked())
			{
				return 0;
			}

			yield();
		}
		else
		{
			result += sent;
			start = MonoTime.currTime;
		}
	} while (socket.isAlive && result < buffer.length && sent < 1 && MonoTime.currTime - start < timeout);

	return result;
}

/**
	Pseudo-blocking version of `Socket.connect` for non-blocking
	sockets which calls `yield` until the connection has been established
	or an error has occurred.

	Params:
		socket = The socket to connect on.
		address = The address to connect to.
*/
void connectAsync(scope Socket socket, scope Address address)
{
	enforce(socket !is null);
	enforce(!socket.blocking);

	Duration timeout;
	socket.getOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, timeout);
	enforce(timeout >= 1.msecs, "SocketOption.RCVTIMEO must be at least 1ms");

	const start = MonoTime.currTime;

	auto set = new SocketSet();
	socket.connect(address);

	do
	{
		set.add(socket);

		if (Socket.select(null, set, null, 1.msecs) > 0)
		{
			break;
		}

		yield();
	} while (socket.isAlive && MonoTime.currTime - start < timeout);
}

/**
	Peek at incoming data on the specified `Socket`.

	Params:
		socket = The socket to read from.
		buffer = The buffer to store the peeked data.

	Returns:
		The number of bytes read, `0` if the connection has been closed,
		or `Socket.ERROR` on failure.
*/
@safe ptrdiff_t peek(scope Socket socket, scope void[] buffer)
{
	auto result = socket.receive(buffer, SocketFlags.PEEK);

	if (!result)
	{
		return 0;
	}

	if (result > 0 || wouldHaveBlocked())
	{
		return result;
	}

	return 0;
}

/**
	Convenience function for writing lines to `Appender`
	
	Params:
		output = The appender to write the line to.
		args = Arguments to add to the line.`
*/
@safe void writeln(T, A...)(scope ref Appender!T output, A args)
{
	foreach (a; args)
	{
		output.put(a);
	}

	output.put(HTTP_BREAK);
}

/**
	Convenience function for writing lines to a `Socket``

	Params:
		socket = The socket to write the line to.
		args = Arguments to add to the line.
*/
auto writeln(A...)(scope Socket socket, A args)
{
	Appender!string builder;
	builder.writeln(args);
	return socket.sendAsync(builder.data);
}
