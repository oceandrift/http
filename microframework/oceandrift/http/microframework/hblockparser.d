/++
    Extension of hparser to parse whole headers
 +/
module oceandrift.http.microframework.hblockparser;

import oceandrift.http.microframework.hparser;
import oceandrift.http.message : hbuffer, hstring, MultiBuffer, MultiBufferView;

@safe pure nothrow:

///
HeaderBlockParser!linebreak parseHeaderBlock(string linebreak = "\r\n")(MultiBufferView input)
{
    return HeaderBlockParser!linebreak(input);
}

struct HeaderBlockParser(string linebreak)
{
@safe pure nothrow:

    private enum lb = cast(immutable(ubyte)[]) linebreak;

    private
    {
        MultiBufferView _input;

        size_t _bytesRead = 0;

        bool _empty = true;
        Header _front;
    }

    this(MultiBufferView input)
    {
        _input = input;
        _empty = false;
        popFront();
    }

    ///
    bool empty() @nogc
    {
        return _empty;
    }

    ///
    Header front() @nogc
    {
        return _front;
    }

    ///
    void popFront()
    {
        import std.algorithm : countUntil;

        // no input left?
        if (_input.empty)
            return markEndOfHeader();

        // determine position of next linebreak
        ptrdiff_t idxEndOfLine = _input.countUntil(lb);
        size_t popN;

        // empty line?
        if (idxEndOfLine == 0)
        {
            _bytesRead += lb.length;
            return markEndOfHeader();
        }

        // no linebreak at all?
        if (idxEndOfLine < 0)
        {
            idxEndOfLine = _input.length;
            popN = idxEndOfLine;
        }
        else
            popN = idxEndOfLine + lb.length;

        // slice current line
        hstring line = cast(hstring) _input[0 .. idxEndOfLine];

        // parse header
        _front = parseHeader(line);

        // pop off current header
        foreach (idx; 0 .. popN)
            _input.popFront();

        _bytesRead += popN;
    }

    auto input(){return _input;}// TODO

    ///
    size_t bytesRead() @nogc
    {
        return _bytesRead;
    }

    private void markEndOfHeader()
    {
        _empty = true;
    }
}

version (unittest)
{
    import oceandrift.http.microframework.kvp;

    private bool compareHeader(Header actual, hstring expectedName, hstring expectedMain, KeyValuePair[] expectedParams)
    {
        if (actual.name != expectedName)
            return false;

        if (actual.value.main != expectedMain)
            return false;

        auto actualParams = actual.value.params;
        foreach (expectedParam; expectedParams)
        {
            if (actualParams.empty)
                return false;

            if (actualParams.front != expectedParam)
                return false;

            actualParams.popFront();
        }

        return true;
    }
}

unittest
{
    auto hbp = parseHeaderBlock(MultiBufferView(MultiBuffer(
            "Content-Type: text/plain; charset=UTF-8\r\nCache-Control: no-cache, no-store\r\n\r\n"
        ))
    );

    assert(!hbp.empty);
    assert(compareHeader(
            hbp.front,
            "Content-Type", "text/plain", [KeyValuePair("charset", "UTF-8")]));
    hbp.popFront();

    assert(!hbp.empty);
    assert(compareHeader(
            hbp.front,
            "Cache-Control", "no-cache, no-store", []));
    hbp.popFront();

    assert(hbp.empty);
    assert(hbp.bytesRead == 78);
}

unittest
{
    auto hbp = parseHeaderBlock(MultiBufferView(
            MultiBuffer(
            "Content-Type: text/plain\r\nCache-Control: no-cache\r\n"))
    );

    assert(!hbp.empty);
    assert(compareHeader(hbp.front, "Content-Type", "text/plain", []));
    hbp.popFront();

    assert(!hbp.empty);
    assert(compareHeader(hbp.front, "Cache-Control", "no-cache", []));
    hbp.popFront();

    assert(hbp.empty);
    assert(hbp.bytesRead == 51);
}

unittest
{
    auto hbp = parseHeaderBlock(MultiBufferView(
            MultiBuffer(
            "Content-Type: text/plain\r\n\r\nCache-Control: no-cache"
        ))
    );

    assert(!hbp.empty);
    assert(compareHeader(hbp.front, "Content-Type", "text/plain", []));
    hbp.popFront();
    assert(hbp.empty);
    assert(hbp.bytesRead == 28);
}

unittest
{
    auto hbp = parseHeaderBlock(MultiBufferView(MultiBuffer("Content-Type: text/plain")));

    assert(!hbp.empty);
    assert(compareHeader(hbp.front, "Content-Type", "text/plain", []));
    hbp.popFront();
    assert(hbp.empty);
    assert(hbp.bytesRead == 24);
}

unittest
{
    auto hbp = parseHeaderBlock!"\n"(MultiBufferView(
            MultiBuffer(
            "Content-Type: text/plain\nCache-Control: no-cache\n\n"))
    );

    assert(!hbp.empty);
    assert(compareHeader(hbp.front, "Content-Type", "text/plain", []));
    hbp.popFront();

    assert(!hbp.empty);
    assert(compareHeader(hbp.front, "Cache-Control", "no-cache", []));
    hbp.popFront();

    assert(hbp.empty);
    assert(hbp.bytesRead == 50);
}

unittest
{
    auto hbp = parseHeaderBlock(MultiBufferView(MultiBuffer("\r\nContent-Type: text/plain")));
    assert(hbp.empty); // no header
    assert(hbp.bytesRead == 2);
}

unittest
{
    auto hbp = parseHeaderBlock(MultiBufferView(MultiBuffer("")));
    assert(hbp.empty);
    assert(hbp.bytesRead == 0);
}
