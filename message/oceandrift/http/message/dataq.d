/++
    # Data Queues

    Data Queues are objects that data can be written to, read from etc.

    They are similar to $(I Streams).
    Their main difference is that reading and writing are independant operations for data queues.
    Writing to a data queue will have no impact on the (internal) reading data pointer/offset.

    Write operations always enqueue data on the end of the current queue.
    For read operations on the other hand it is possible to rewind to the beginning if the queue is rereadable.
 +/
module oceandrift.http.message.dataq;

import oceandrift.http.message.htype;

@safe:

/++
    A Data Queue
 +/
interface DataQ
{
@safe:

    /++
        Closes the queue

        A closed queue must not be read from or written to.
     +/
    void close();

    /++
        Determines whether the queue has been closed
     +/
    bool closed();

    /++
        Determines whether there is currently any data left to read
     +/
    bool empty();

    /++
        Reads data into a buffer

        Returns:
            The number of bytes read
     +/
    size_t read(scope ubyte[]);

    /++
        Determines the known length of the current queue

        Returns:
            $(LIST
                * The number of bytes available
                * or `< 0` if the length $(B is not known)
            )
     +/
    long knownLength();

    /++
        Rewinds the read-pointer to the start of the queue.
        The next call to [read] will read data from the beginning of the queue.
     +/
    void rewindReading();

    /++
        Copies the currently queued data into another queue
     +/
    void copyTo(DataQ);

    /++
        Enqueues the passed data
     +/
    void write(hbuffer);

    /// ditto
    void write(hstring);
}

hstring toArray(DataQ dataQ)
{
    immutable long length = dataQ.knownLength;

    if (length == 0)
        return null;

    if (length > 0)
    {
        ubyte[] buffer = new ubyte[](length);
        immutable size_t bytesRead = dataQ.read(buffer);
        return cast(hstring) buffer[0 .. bytesRead];
    }

    size_t bytesReadTotal = 0;
    ubyte[] buffer = new ubyte[](64);
    while (true)
    {
        bytesReadTotal += dataQ.read(buffer[bytesReadTotal .. $]);
        if (dataQ.empty)
            break;

        buffer.length += (buffer.length / 2);
    }

    return cast(hstring) buffer[0 .. bytesReadTotal];
}

///
final class FileReaderDataQ : DataQ
{
    import std.stdio : File;

@safe:
    private
    {
        File _file;
    }

    public this(string path, string mode = "r")
    {
        _file = File(path, mode);
    }

    bool closed() pure nothrow
    {
        return !_file.isOpen;
    }

    void close()
    {
        return _file.close();
    }

    bool empty() pure
    {
        return _file.eof;
    }

    size_t read(scope ubyte[] buffer)
    {
        return _file.rawRead(buffer).length;
    }

    ptrdiff_t knownLength()
    {
        immutable ulong fLength = _file.size;
        if (fLength == ulong.max)
            return -1;

        return fLength - _file.tell;
    }

    void rewindReading()
    {
        return _file.rewind();
    }

    void copyTo(DataQ target)
    {
        enum chunkSize = 1024 * 4;
        auto buffer = new ubyte[](chunkSize);

        while (!_file.eof)
        {
            hbuffer readData = _file.rawRead(buffer);
            target.write(readData);
        }
    }

    void write(hbuffer)
    {
        assert(false);
    }

    void write(hstring)
    {
        assert(false);
    }
}
