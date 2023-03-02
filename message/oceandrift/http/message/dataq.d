/++
    # Data Queues

    Data Queues are objects that data can be written to, read from etc.

    They are similar to $(I Streams).
    Their main difference is that reading and writing are independant operations for data queues.
    Writing to a data queue will have no impact on the (internal) reading data pointer/offset.

    Write operations always enqueue data on the end of the current queue.
    For read operations on the other hand it is possible to rewind to the beginning if the queue is rereadable.

    This module defines a set of interfaces which enable all sorts of features for data queues.
    [AnyDataQ] is the base for all of them.
    [ReadableDataQ] enables reading; [WriteableDataQ] enables writing.
 +/
module oceandrift.http.message.dataq;

import oceandrift.http.message.htype;

@safe:

/++
    A Data Queue
 +/
interface DataQ : RereadWriteableDataQ, CopyableDataQ
{
}

interface ForwardDataQ
{
    ForwardDataQ save();
}

/++
    A Data Queue that can be read from the beginning multiple times (by calling `rewindRead`)
    and written to
 +/
interface RereadWriteableDataQ : ReadWriteableDataQ, RereadableDataQ
{
}

/++
    A Data Queue that can be read from and written to
 +/
interface ReadWriteableDataQ : ReadableDataQ, WriteableDataQ
{
}

/++
    Data Queue

    Base interface for all Data Queues
 +/
interface AnyDataQ
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
}

/++
    A Data Queue that can be read from
 +/
interface ReadableDataQ : AnyDataQ
{
@safe:
    /++
        Determines whether there is currently any data left to read
     +/
    bool empty();

    /++
        Reads data into a buffer

        Returns:
            $(LIST
                * The number of bytes read
                * or `< 0` on failure
            *)
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
    ptrdiff_t knownLength();
}

/++
    A Data Queue that can be read from the beginning multiple times
 +/
interface RereadableDataQ : ReadableDataQ
{
@safe:
    /++
        Rewinds the read-pointer to the start of the queue.
        The next call to [read] will read data from the beginning of the queue.
     +/
    void rewindReading();
}

/++
    A Data Queue that can be directly copied into another one
 +/
interface CopyableDataQ : AnyDataQ
{
@safe:
    /++
        Copies the currently queued data into another queue
     +/
    void copyTo(WriteableDataQ);

    /// ditto
    void copyTo(ScopeWriteableDataQ);
}

/++
    A Data Queue that data can be written to
    
    Written data is enqueued at the end (“appended”).
 +/
interface WriteableDataQ : AnyDataQ
{
@safe:
    /++
        Enqueues the passed data
     +/
    void write(hbuffer);
}

/// ditto
interface ScopeWriteableDataQ : AnyDataQ
{
@safe:
    /++
        Enqueues the passed `scope` data
     +/
    void write(scope hbuffer);
}

final class ProxyDataQ : DataQ
{
    private
    {
        AnyDataQ _dataQ;
    }

    public this(AnyDataQ dataQ) pure nothrow @nogc
    {
        _dataQ = dataQ;
    }

    public void replace(AnyDataQ dataQ) pure nothrow @nogc
    {
        _dataQ = dataQ;
    }

    // DataQ
    public
    {
        void close()
        {
            return _dataQ.close();
        }

        bool closed()
        {
            return _dataQ.closed();
        }

        bool empty()
        {
            if (auto dataQ = cast(ReadableDataQ) _dataQ)
                return dataQ.empty;

            return true;
        }

        size_t read(scope ubyte[] buffer)
        {
            if (auto dataQ = cast(ReadableDataQ) _dataQ)
                return dataQ.read(buffer);

            return 0;
        }

        ptrdiff_t knownLength()
        {
            if (auto dataQ = cast(ReadableDataQ) _dataQ)
                return dataQ.knownLength;

            return ptrdiff_t.min;
        }

        void rewindReading()
        {
            if (auto dataQ = cast(RereadableDataQ) _dataQ)
                return dataQ.rewindReading;

            assert(false, "Underlying DataQ is not rereadable");
        }

        void write(hbuffer data)
        {
            if (auto dataQ = cast(WriteableDataQ) _dataQ)
                return dataQ.write(data);

            assert(false, "Underlying DataQ is not writeable");
        }

        void copyTo(WriteableDataQ target) @trusted
        {
            if (auto dataQ = cast(CopyableDataQ) _dataQ)
                return dataQ.copyTo(target);

            assert(false);
        }

        void copyTo(ScopeWriteableDataQ target) @trusted
        {
            if (auto dataQ = cast(CopyableDataQ) _dataQ)
                return dataQ.copyTo(target);

            assert(false);
        }
    }

    // convenience
    public
    {
        void write(hstring data)
        {
            return this.write(cast(hbuffer) data);
        }

        void write(Args...)(Args data) if (Args.length > 1)
        {
            import std.conv : to;

            static foreach (d; data)
            {
                static assert(__traits(compiles, cast(hbuffer)(typeof(d)
                        .init)),
                    "Incompatible type: " ~ typeof(d).stringof
                );

                this.write(cast(hbuffer) d);
            }
        }

    }
}

///
final class FileReaderDataQ : CopyableDataQ, RereadableDataQ
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

    void copyTo(WriteableDataQ target)
    {
        enum chunkSize = 1024 * 4;
        auto buffer = new ubyte[](chunkSize);

        while (!_file.eof)
        {
            hbuffer readData = _file.rawRead(buffer);
            target.write(readData);
        }
    }

    void copyTo(ScopeWriteableDataQ target)
    {
        enum chunkSize = 1024;
        ubyte[chunkSize] buffer;

        while (!_file.eof)
        {
            hbuffer readData = _file.rawRead(buffer);
            target.write(readData);
        }
    }
}
