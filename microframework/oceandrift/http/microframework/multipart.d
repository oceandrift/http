/++
    Multipart data handling
 +/
module oceandrift.http.microframework.multipart;

import std.string : indexOf;
import oceandrift.http.message;
import oceandrift.http.microframework.uri;

public import oceandrift.http.message : equalsCaseInsensitive, hstring;
public import oceandrift.http.microframework.kvp;

@safe pure nothrow:

private
{
    enum delimiterPrefix = "\r\n--";
    enum crlf = "\r\n";
}

struct MultipartFile
{
    /++
        Name

        $(PITFALL
            Might not be unique.
        )

        Standards:
            See RFC 7578, 4.3. “Multiple Files for One Form Field”
     +/
    hstring name;

    hstring contentDisposition;
    hstring contentType = "text/plain";

    /++
        Content-Transfer-Encoding
        
        Standards:
            RFC 7578, 4.7.:
                Luckily, this has been deprecated already,
                plus “Currently, no deployed implementations that send such bodies have been discovered”.
     +/
    hstring contentTransferEncoding;

    ubyte[] data;
}

bool popCompare(ref MultiBufferView range, hbuffer expected) @nogc
{
    while (expected.length > 0)
    {
        if (range.empty)
            return false; // (expected.length == 0) --> known to be false here

        if (range.front != expected[0])
            return false;

        range.popFront();
        expected = expected[1 .. $];
    }

    return true;
}

bool popCompare(ref MultiBufferView range, hstring expected) @nogc
{
    return popCompare(range, cast(hbuffer) expected);
}

unittest
{
    hstring x = "01234567";
    auto mb = MultiBuffer();
    mb.write(x);
    auto mbv = MultiBufferView(mb);

    assert(mbv.popCompare("0123"));
    assert(mbv.popCompare("4"));
    assert(mbv.popCompare("56"));
    assert(!mbv.popCompare("8"));
}

struct MultipartParser
{
@safe pure nothrow:

    private
    {
        hstring _boundary;
        MultiBufferView _data;

        bool _empty = true;
        MultipartFile _front;
    }

    this(MultiBuffer multipartData, hstring boundary)
    {
        _boundary = boundary;
        _data = MultiBufferView(multipartData);
        _empty = false;

        popFrontInit();
    }

    bool empty() @nogc
    {
        return _empty;
    }

    MultipartFile front() @nogc
    {
        return _front;
    }

    private void popFrontInit()
    {
        if (!_data.popCompare("--")) // invalid?
        {
            _empty = true;
            return;
        }

        if (!_data.popCompare(_boundary)) // invalid?
        {
            _empty = true;
            return;
        }

        if (!_data.popCompare(crlf)) // invalid?
        {
            _empty = true;
            return;
        }
    }

    void popFront()
    {
        _front = MultipartFile();

        auto clone = _data;
        size_t bytes = 0;

        // parse header
        size_t sep = 0;
        while (true)
        {
            if (_data.empty)
            {
                // invalid input, error
                _empty = true;
                return;
            }

            if (_data.front == crlf[0])
            {
                _data.popFront();
                if (_data.front == crlf[1])
                {
                    // end of header line
                    _data.popFront();

                    if (sep == 0) // no separator?
                    {
                        // end of header
                        if (bytes == 0)
                            break;

                        // or invalid?
                        goto pfParseHeaderRestore;
                    }

                    // allocate buffer for continuously storing the header data
                    auto buffer = new ubyte[](bytes);

                    // copy over
                    foreach (ref b; buffer)
                    {
                        b = clone.front;
                        clone.popFront();
                    }

                    // slice header name
                    const headerName = buffer[0 .. sep];

                    // process header
                    enum lctCD = LowerCaseToken.makeConverted("Content-Disposition");
                    enum lctCT = LowerCaseToken.makeConverted("Content-Type");
                    enum lctCTE = LowerCaseToken.makeConverted("Content-Transfer-Encoding");
                    if (equalsCaseInsensitive(headerName, lctCD))
                    {
                        _front.contentDisposition = parseMultipartHeaderValue(buffer, sep);
                    }
                    else if (equalsCaseInsensitive(headerName, lctCT))
                        _front.contentType = parseMultipartHeaderValue(buffer, sep);
                    else if (equalsCaseInsensitive(headerName, lctCTE))
                        _front.contentTransferEncoding = parseMultipartHeaderValue(buffer, sep);
                    //else -> discard

                pfParseHeaderRestore:
                    clone = _data;
                    bytes = 0;
                    sep = 0;
                    continue;
                }
            }

            if (_data.front == ':')
            {
                sep = bytes;
            }

            ++bytes;
            _data.popFront();
        }

        clone = _data;
        bytes = 0;

        debug
        {
            import std.stdio : writeln;

            try
            {
                writeln(_front);
                assert(0);
            }
            catch (Exception)
            {
            }
        }

        size_t delimiterPrefixSearchOffset = 0;
        size_t boundarySearchOffset = 0;

        while (!_data.empty)
        {
            if (delimiterPrefixSearchOffset < delimiterPrefix.length)
            {
                if (_data.front == delimiterPrefix[delimiterPrefixSearchOffset])
                    ++delimiterPrefixSearchOffset;
                else
                    delimiterPrefixSearchOffset = 0;
            }
            else if (boundarySearchOffset < _boundary.length)
            {
                if (_data.front == _boundary[boundarySearchOffset])
                    ++boundarySearchOffset;
                else
                {
                    boundarySearchOffset = 0;
                    delimiterPrefixSearchOffset = 0;
                }
            }
            else
            {
                // found
                bytes -= delimiterPrefix.length + _boundary.length;
                _front = MultipartFile();
            }

            ++bytes;
            _data.popFront();
        }

        if (_data.popCompare(delimiterPrefix))
        {
            if (_data.popCompare(_boundary))
                if (_data.front == '-')
                    return;
        }
    }
}

private hstring parseMultipartHeaderValue(hbuffer raw, size_t sep) @nogc
{
    immutable size_t offset = (raw[sep + 1] == ' ') ? sep + 2 : sep + 1; // skip ": " separator (quirks support: ":")
    return cast(hstring) raw[offset .. $];
}

private hstring nameFromContentDisposition(hstring contentDisposition) @nogc
{
    // TODO
}

hstring determineMultipartBoundary(const hstring contentType) @nogc
{
    import oceandrift.http.microframework.hparser : parseHeaderValue;

    foreach (param; parseHeaderValue(contentType).params)
        if (param.key == "boundary")
            return param.value;

    return null;
}

unittest
{
    assert(determineMultipartBoundary(`multipart/form-data; boundary=something`) == "something");
    assert(determineMultipartBoundary(`multipart/form-data; boundary=something `) == "something");
    assert(determineMultipartBoundary(`multipart/form-data; boundary="something"`) == "something");
    assert(determineMultipartBoundary(
            `multipart/form-data; hosntial=gatsch; boundary="something"`) == "something");
    assert(determineMultipartBoundary(`multipart/form-data; boundary="something" `) == "something");
    assert(determineMultipartBoundary(`multipart/form-data; boundary="something" z4`) == "something");
    assert(determineMultipartBoundary(
            `multipart/form-data; oachkatzl=schwoaf boundary="something"`) is null);
    assert(determineMultipartBoundary(
            `multipart/form-data; boundary="something" oachkatzl="schwoaf"`) == "something");
    assert(determineMultipartBoundary(`multipart/form-data;oachkatzl="schwoaf"`) is null);
    assert(determineMultipartBoundary(`multipart/form-data;oachkatzl=schwoaf;party`) is null);
    assert(determineMultipartBoundary(`multipart/form-data;boundary="some;thing"`) == "some;thing");
    assert(determineMultipartBoundary(
            `multipart/form-data;boundary=some0thing;party`) == "some0thing");
    assert(determineMultipartBoundary(`boundary=_1234_`) is null);
    assert(determineMultipartBoundary(`multipart/form-data; boundary=----z-1234`) == "----z-1234");
    assert(determineMultipartBoundary(`multipart/form-data; boundary="----z-1234"`) == "----z-1234");
    assert(determineMultipartBoundary(`multipart/form-data; coboundary=b0undary`) is null);
    assert(determineMultipartBoundary(
            `multipart/form-data; coboundary=b0undary; boundary="boundary"`) == "boundary");
    assert(determineMultipartBoundary(`multipart/form-data; garbage="a=b boundary=xyz"; boundary="sth"`) == "sth");
}
