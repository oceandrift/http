module oceandrift.http.message.multibuffer;

import oceandrift.http.message.dataq;
import oceandrift.http.message.htype;

@safe:

/++
    List of multiple buffers

    Stores slices to (potentially indepenant) buffers.
 +/
struct MultiBuffer
{
@safe pure nothrow:

    private
    {
        enum defaultReserve = 16;

        hbuffer[] _bufferList;
        size_t _bufferListUsedLength = 0;
    }

    this(hstring initialContent)
    {
        this.append(initialContent);
    }

    this(hbuffer initialContent)
    {
        this.append(initialContent);
    }

    /++
        Current capacity of the internal buffer list

        $(TIP
            Probably not what you were looking for.
        )

        See_Also:
        $(LIST
            * dataLength – length of all data from all buffers
            * length – number of buffers in the list
        )
     +/
    size_t capacity() const @nogc
    {
        return _bufferList.length;
    }

    /++
        Number of buffers

        See_Also:
            [dataLength]
     +/
    size_t length() const @nogc
    {
        return _bufferListUsedLength;
    }

    /++
        Reserves a certain extra capacity in the list to be available without further allocations
     +/
    void reserve(size_t n)
    {
        _bufferList.length += n;
    }

    /++
        Appends the passed buffer to the buffer list
     +/
    void append(T)(T buffer) if (__traits(compiles, (T b) => cast(hbuffer) b))
    {
        this.ensureCapacity();

        _bufferList[_bufferListUsedLength] = cast(hbuffer) buffer;
        ++_bufferListUsedLength;
    }

    /++
        Allocates a new buffer, copies over the data from the passed buffer
        and appends it the the buffer list
     +/
    void appendCopy(T)(T buffer) if (__traits(compiles, (T b) => cast(hbuffer) b))
    {
        ubyte[] bCopy = (cast(hbuffer) buffer).dup;

        return this.append(bCopy);
    }

    void write(Buffers...)(Buffers buffers)
    {
        static foreach (buffer; buffers)
        {
            static assert(
                __traits(compiles, (typeof(buffer) b) => cast(hbuffer) b),
                "Incompatible buffer type: `" ~ typeof(buffer).stringof ~ '`'
            );
            this.append(buffer);
        }
    }

    /++
        Appends a buffer to the buffer list
     +/
    void opOpAssign(string op : "~", T)(T buffer)
    {
        return this.append(buffer);
    }

    /++
        Returns:
            The buffer at the requested position
     +/
    ref hbuffer opIndex(size_t index)
    {
        return _bufferList[index];
    }

    /++
        Calculates the total length of all data from all linked buffers
     +/
    size_t dataLength() inout @nogc
    {
        size_t length = 0;
        foreach (buffer; _bufferList[0 .. _bufferListUsedLength])
            length += buffer.length;

        return length;
    }

    deprecated("Use .toArray() instead") alias data = toArray;

    /++
        Allocates a new “big” buffer containing all data from all linked buffers
     +/
    immutable(ubyte)[] toArray() inout
    {
        ubyte[] output = new ubyte[](this.dataLength);

        size_t i = 0;
        foreach (buffer; _bufferList[0 .. _bufferListUsedLength])
        {
            output[i .. (i + buffer.length)] = buffer[0 .. $];
            i += buffer.length;
        }

        return output;
    }

    /++
        Allocates a new string containing all data from all linked buffers
     +/
    string toString() inout
    {
        return cast(string) this.data();
    }

    public @nogc // range
    {
        ///
        bool empty() inout
        {
            return (_bufferListUsedLength == 0);
        }

        ///
        hbuffer front() inout
        {
            return _bufferList[0];
        }

        ///
        void popFront()
        {
            _bufferList = _bufferList[1 .. $];
            --_bufferListUsedLength;
        }
    }

private:

    void ensureCapacity()
    {
        if (_bufferList.length != _bufferListUsedLength)
            return;

        immutable size_t toReserve = (_bufferList.length == 0)
            ? defaultReserve : (_bufferListUsedLength + (_bufferListUsedLength / 2));

        this.reserve(toReserve);
    }
}

unittest
{
    MultiBuffer mb;
    assert(mb.empty);
    assert(mb.capacity == 0);
    assert(mb.length == 0);
    assert(mb.dataLength == 0);
    assert(mb.data == []);

    char[] a = ['0', '1', '2', '3'];
    mb.appendCopy(a);
    assert(!mb.empty);
    assert(mb.length == 1);
    assert(mb.capacity == mb.defaultReserve);
    assert(mb.dataLength == a.length);
    assert(mb.data == a);
    a[0] = '9';
    assert(mb.front == "0123");

    char[] b = ['4', '5', '6', '7'];
    mb.append(b);
    assert(!mb.empty);
    assert(mb.length == 2);
    assert(mb.capacity == mb.defaultReserve);
    assert(mb.dataLength == (a.length + b.length));
    assert(mb.data == "01234567");

    b[0] = '9';
    assert(mb.data == "01239567");
}

/++
    Access MultiBuffers as if they were a single continuous buffer
 +/
struct MultiBufferView
{
@safe pure nothrow:

    private
    {
        MultiBuffer _mb;
        hbuffer _currentBuffer;
    }

    ///
    this(MultiBuffer mb) @nogc
    {
        _mb = mb;

        if (_mb.empty)
            return;

        _currentBuffer = _mb.front;
        advanceFront();
    }

    ///
    bool empty() @nogc
    {
        return _mb.empty;
    }

    ///
    ubyte front() @nogc
    {
        return _currentBuffer[0];
    }

    ///
    void popFront() @nogc
    {
        _currentBuffer = _currentBuffer[1 .. $];
        return advanceFront();
    }

    ///
    MultiBufferView save() @nogc
    {
        return this;
    }

    ///
    ubyte opIndex(size_t index) @nogc
    {
        // start scanning from the current position in the current buffer
        if (index < _currentBuffer.length)
            return _currentBuffer[index];

        // not there yet, substract difference from search position
        index -= _currentBuffer.length;

        // prepare next buffer
        MultiBuffer mb = _mb;
        mb.popFront();

        // scan buffer by buffer
        while (!mb.empty)
        {
            if (index < mb.front.length)
                return mb.front[index];

            index -= mb.front.length;
            mb.popFront();
        }

        assert(false, "Out of range");
    }

    ///
    const(ubyte)[] opSlice(size_t start, size_t end)
    {
        if (end < start)
            assert(false, "Slice has a larger lower index than upper index");

        // Is the requested slice continuously contained in the current buffer?
        if (end <= _currentBuffer.length)
            return _currentBuffer[start .. end];

        // No

        // Is the start of the requested slice beyond the current buffer?
        if (start >= _currentBuffer.length)
        {
            // advance a copy of this view to the next buffer and recursively recheck

            // calculate new indices
            immutable size_t nextStart = start - _currentBuffer.length;
            immutable size_t nextEnd = end - _currentBuffer.length;

            // copy & advance
            MultiBufferView clone = this.save();
            clone._currentBuffer = []; // skip current buffer
            clone.advanceFront();

            if (clone.empty)
                assert(false, "Slice out of range");

            return clone.opSlice(nextStart, nextEnd);
        }

        // Memory allocation needed

        // Allocate buffer
        immutable size_t outputSize = end - start;
        ubyte[] wholeOutputBuffer = new ubyte[](outputSize);

        // Copy element from _currentBuffer to the new outputBuffer
        immutable size_t elementsFromFirstBuffer = _currentBuffer.length - start;
        wholeOutputBuffer[0 .. elementsFromFirstBuffer] = _currentBuffer[start .. $];

        MultiBufferView clone = this.save();
        ubyte[] outputBuffer = wholeOutputBuffer[elementsFromFirstBuffer .. $];

        do
        {
            // Advance clone to its next internal buffer
            clone._currentBuffer = [];
            clone.advanceFront();

            // Clone already empty?
            if (clone.empty)
                assert(false, "Slice out of range");

            // Determine how many bytes to copy
            immutable size_t idxCopyEnd = (outputBuffer.length < clone._currentBuffer.length)
                ? outputBuffer.length : clone._currentBuffer.length;

            // Copy
            outputBuffer[0 .. idxCopyEnd] = clone._currentBuffer[0 .. idxCopyEnd];

            // Advance output buffer slice
            outputBuffer = outputBuffer[idxCopyEnd .. $];
        }
        while (outputBuffer.length > 0);

        return wholeOutputBuffer;
    }

    ///
    size_t length() @nogc
    {
        MultiBufferView clone = this.save();

        size_t total = 0;
        while (!clone.empty)
        {
            total += clone._currentBuffer.length;
            clone._currentBuffer = [];
            clone.advanceFront();
        }

        return total;
    }

    ///
    size_t opDollar() @nogc
    {
        return this.length;
    }

    private void advanceFront() @nogc
    {
        while (_currentBuffer.length == 0)
        {
            _mb.popFront();

            if (_mb.empty)
                break;

            _currentBuffer = _mb.front;
        }
    }
}

unittest
{
    auto mb = MultiBuffer();

    {
        auto mbv = MultiBufferView(mb);
        assert(mbv.empty);
    }

    mb.write("asdf", "1234", "q", "", "0000000000!");

    auto mbv = MultiBufferView(mb);

    assert(mbv[0] == 'a');
    assert(mbv[3] == 'f');
    assert(mbv[4] == '1');
    assert(mbv[8] == 'q');
    assert(mbv[9] == '0');
    assert(mbv[19] == '!');

    assert(!mbv.empty);
    assert(mbv.front == 'a');
    mbv.popFront();
    assert(!mbv.empty);
    assert(mbv.front == 's');
    mbv.popFront();
    assert(!mbv.empty);
    assert(mbv.front == 'd');
    mbv.popFront();
    assert(!mbv.empty);
    assert(mbv.front == 'f');
    mbv.popFront();
    assert(!mbv.empty);
    assert(mbv.front == '1');
    static foreach (idx; 0 .. 4)
        mbv.popFront();
    assert(mbv.front == 'q');
    mbv.popFront();
    assert(!mbv.empty);
    assert(mbv.front == '0');
    static foreach (idx; 0 .. 10)
        mbv.popFront();
    assert(!mbv.empty);
    assert(mbv.front == '!');
    mbv.popFront();
    assert(mbv.empty);
}

///
unittest
{
    auto mb = MultiBuffer();
    mb.write("", "01");

    auto mbv = MultiBufferView(mb);
    assert(!mbv.empty);
    assert(mbv.front == '0');
    assert(mbv[0] == '0');
    assert(mbv[1] == '1');

    mbv.popFront();
    assert(mbv.front == '1');
    assert(mbv[0] == '1');

    mbv.popFront();
    assert(mbv.empty);
}

///
unittest
{
    auto mb = MultiBuffer();
    mb.write("1234");

    auto mbv = MultiBufferView(mb);
    assert(mbv.length == 4);

    assert(mbv[0 .. 1] == "1");
    assert(mbv[1 .. 2] == "2");
    assert(mbv[1 .. 3] == "23");
    assert(mbv[1 .. 4] == "234");
    assert(mbv[0 .. 4] == "1234");

    mbv.popFront();
    assert(mbv.length == 3);
    mbv.popFront();
    assert(mbv.length == 2);
    mbv.popFront();
    assert(mbv.length == 1);
    mbv.popFront();
    assert(mbv.length == 0);
    assert(mbv.empty);
    assert(mbv[0 .. $] == []);
}

///
unittest
{
    auto mb = MultiBuffer();
    mb.write("0123", "4567");

    auto mbv = MultiBufferView(mb);
    assert(mbv.length == 8);

    assert(mbv[0 .. 4] == "0123");
    assert(mbv[4 .. 6] == "45");
    assert(mbv[5 .. 8] == "567");

    // these will allocate:
    assert(mbv[2 .. 5] == "234");
    assert(mbv[0 .. 8] == "01234567");
    assert(mbv[3 .. 5] == "34");
}

///
unittest
{
    auto mb = MultiBuffer();
    mb.write("0123", "4567", "89");

    auto mbv = MultiBufferView(mb);
    assert(mbv.length == mb.dataLength);

    assert(mbv[0 .. 8] == "01234567");
    assert(mbv[0 .. 9] == "012345678");
    assert(mbv[3 .. 9] == "345678");
    assert(mbv[7 .. 9] == "78");
    assert(mbv[4 .. 10] == "456789");
    assert(mbv[4 .. $] == "456789");

    mbv.popFront();
    assert(mbv.length == 9);
    assert(mbv[0 .. 8] == "12345678");
}

/++
    Data Queue implementation that keeps all data in memory
 +/
final class InMemoryDataQ : DataQ
{
@safe:

    private
    {
        bool _closed = false;
        MultiBuffer _mb;

        size_t _readOffsetBuffer = 0;
        size_t _readOffsetBufferBytes = 0;
    }

    public this() pure nothrow @nogc
    {
        _mb = MultiBuffer();
    }

    public this(hbuffer initialContent) pure nothrow
    {
        _mb = MultiBuffer(initialContent);
    }

    public this(hstring initialContent) pure nothrow
    {
        _mb = MultiBuffer(initialContent);
    }

    public this(MultiBuffer initialContent) pure nothrow @nogc
    {
        _mb = initialContent;
    }

    InMemoryDataQ save()
    {
        auto copy = new InMemoryDataQ();
        copy._mb = _mb;
        copy._readOffsetBuffer = _readOffsetBuffer;
        copy._readOffsetBufferBytes = _readOffsetBufferBytes;
        copy._closed = _closed;
        return copy;
    }

    void close() pure nothrow @nogc
    {
        _closed = true;
    }

    bool closed() pure nothrow @nogc
    {
        return _closed;
    }

    void write(hbuffer input) pure nothrow
    {
        _mb.write(input);
    }

    void write(hstring input) pure nothrow
    {
        _mb.write(input);
    }

    bool empty() pure nothrow @nogc
    {
        return (_readOffsetBuffer >= _mb.length);
    }

    size_t read(scope ubyte[] buffer) pure nothrow @nogc
    {
        size_t readBytes = 0;

        while ((buffer.length > 0) && (_readOffsetBuffer < _mb.length))
        {
            hbuffer currentBufferLeft =
                _mb._bufferList[_readOffsetBuffer][_readOffsetBufferBytes .. $];

            if (currentBufferLeft.length >= buffer.length)
            {
                buffer[0 .. $] = currentBufferLeft[0 .. buffer.length];

                readBytes += buffer.length;
                _readOffsetBufferBytes += buffer.length;

                return readBytes;
            }

            buffer[0 .. currentBufferLeft.length] = currentBufferLeft[0 .. $];

            readBytes += currentBufferLeft.length;
            buffer = buffer[currentBufferLeft.length .. $];
            _readOffsetBufferBytes = 0;
            ++_readOffsetBuffer;
        }

        return readBytes;
    }

    long knownLength() pure nothrow @nogc
    {
        long sum = 0;
        foreach (b; _mb._bufferList[_readOffsetBuffer .. _mb.length])
            sum += b.length;
        return sum;
    }

    void rewindReading() pure nothrow @nogc
    {
        _readOffsetBuffer = 0;
        _readOffsetBufferBytes = 0;
    }

    void copyTo(DataQ target)
    {
        if (this.empty)
            return;

        target.write(_mb._bufferList[_readOffsetBuffer][_readOffsetBufferBytes .. $]);
        ++_readOffsetBuffer;
        _readOffsetBufferBytes = 0;

        foreach (buffer; _mb._bufferList[_readOffsetBuffer .. $])
            target.write(buffer);

        // everything read
        _readOffsetBuffer = _mb.length;
    }
}

unittest
{
    DataQ dq = new InMemoryDataQ();

    {
        assert(!dq.closed);
        assert(dq.empty);
        assert(dq.knownLength == 0);
        dq.write(cast(hbuffer)[
                0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70, 0x80, 0x90
            ]);
        assert(!dq.empty);
        assert(dq.knownLength == 9);
    }

    {
        ubyte[2] b;
        assert(dq.read(b) == 2);
        assert(b == [0x10, 0x20]);

        assert(dq.read(b) == 2);
        assert(b == [0x30, 0x40]);
    }

    DataQ dqCopy = (cast(InMemoryDataQ) dq).save();

    dq.write(cast(hbuffer)[0xA0, 0xB0, 0xC0]);

    {
        ubyte[] b = new ubyte[](4);
        assert(dq.read(b) == 4);
        assert(b == [0x50, 0x60, 0x70, 0x80]);
    }

    {
        DataQ dq2 = new InMemoryDataQ();
        dq.copyTo(dq2);

        assert(dq.empty);
        dq.write(cast(hbuffer)[0xD0, 0xE0]);
        assert(!dq.empty);

        ubyte[8] b;
        assert(dq2.read(b) == 4);
        assert(b[0 .. 4] == [0x90, 0xA0, 0xB0, 0xC0]);
        assert(dq2.empty);

        assert(!dq2.closed);
        dq2.close();
        assert(dq2.closed);
    }

    {
        ubyte[] b = new ubyte[](8);
        assert(dq.read(b) == 2);
        assert(b[0 .. 2] == [0xD0, 0xE0]);
        assert(dq.empty);
    }

    {
        dq.rewindReading();
        assert(!dq.empty);

        ubyte[16] b;
        assert(dq.read(b) == 14);
        assert(b[0 .. 14] == [
                0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70, 0x80, 0x90,
                0xA0, 0xB0, 0xC0,
                0xD0, 0xE0,
            ]);

        assert(!dq.closed);
        dq.close();
        assert(dq.closed);
    }

    {
        assert(!dqCopy.closed);
        assert(!dqCopy.empty);

        ubyte[8] b;
        assert(dqCopy.read(b) == 5);
        assert(b[0 .. 5] == [0x50, 0x60, 0x70, 0x80, 0x90]);
        assert(dqCopy.empty);

        dqCopy.close();
        assert(dqCopy.closed);
    }
}
