/++
    Multipart data handling

    Currently limited to multipart/form-data.
 +/
module oceandrift.http.microframework.multipart;

import std.algorithm : countUntil;
import std.range : chain;
import std.string : indexOf;
import oceandrift.http.message;
import oceandrift.http.microframework.hblockparser : parseHeaderBlock;
import oceandrift.http.microframework.uri;

public import oceandrift.http.message : equalsCaseInsensitive, hstring;
public import oceandrift.http.microframework.hparser : HeaderValue;
public import oceandrift.http.microframework.kvp;

@safe pure nothrow:

private
{
    enum delimiterPrefix = "\r\n--";
    enum crlf = "\r\n";
}

/++
    Multipart file data

    The multipart/form-data media type does not support any MIME header
    fields in parts other than Content-Type, Content-Disposition, and (in
    limited circumstances) Content-Transfer-Encoding.  Other header
    fields MUST NOT be included and MUST be ignored.

    Standards:
        RFC 7578
 +/
struct MultipartFile
{
    ///
    HeaderValue contentDisposition;

    ///
    HeaderValue contentType = HeaderValue("text/plain".imdup);

    /++
        Content-Transfer-Encoding
        
        Standards:
            RFC 7578, 4.7.:
                Luckily, this has been deprecated already,
                plus “Currently, no deployed implementations that send such bodies have been discovered”.
     +/
    HeaderValue contentTransferEncoding;

    ///
    hbuffer data;
}

bool popCompare(ref MultiBufferView range, const(ubyte)[] expected) @nogc
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

bool popCompare(ref MultiBufferView range, const(char)[] expected) @nogc
{
    return popCompare(range, cast(const(ubyte)[]) expected);
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

///
MultipartParser parseMultipart(MultiBuffer rawMultipartData, hstring boundary)
{
    return MultipartParser(rawMultipartData, boundary);
}

/// ditto
MultipartParser parseMultipart(MultiBuffer rawMultipartData, const(char)[] boundary)
{
    return parseMultipart(rawMultipartData, hstring(boundary));
}

unittest
{
    // real-world example, data synthesized using Firefox
    auto mpp = parseMultipart(
        MultiBuffer(
            "-----------------------------31396618128806886144188844146"
            ~ "\r\nContent-Disposition: form-data; name=\"message\""
            ~ "\r\n"
            ~ "\r\nqwerty"
            ~ "\r\n-----------------------------31396618128806886144188844146--"),
        "---------------------------31396618128806886144188844146"
    );

    assert(!mpp.empty);

    assert(mpp.front.contentDisposition.main == "form-data");
    assert(!mpp.front.contentDisposition.params.empty);
    assert(mpp.front.contentDisposition.params.front == KeyValuePair("name", "message"));
    mpp.front.contentDisposition.params.popFront();
    assert(mpp.front.contentDisposition.params.empty);

    assert(mpp.front.contentTransferEncoding.main.data is null);
    assert(mpp.front.contentTransferEncoding.params.empty);

    assert(mpp.front.contentType.main == "text/plain");
    assert(mpp.front.contentType.params.empty);

    assert(mpp.front.data == "qwerty");

    mpp.popFront();
    assert(mpp.empty);
}

unittest
{
    // real-world example, data synthesized using Insomnia
    auto mpp = parseMultipart(
        MultiBuffer(
            "--X-INSOMNIA-BOUNDARY"
            ~ "\r\nContent-Disposition: form-data; name=\"message\""
            ~ "\r\n\r\nhello"
            ~ "\r\n--X-INSOMNIA-BOUNDARY"
            ~ "\r\nContent-Disposition: form-data; name=\"ocean\""
            ~ "\r\n\r\ndrift"
            ~ "\r\n--X-INSOMNIA-BOUNDARY--\r\n"),
        "X-INSOMNIA-BOUNDARY"
    );

    assert(!mpp.empty);

    assert(mpp.front.contentDisposition.main == "form-data");
    assert(!mpp.front.contentDisposition.params.empty);
    assert(mpp.front.contentDisposition.params.front == KeyValuePair("name", "message"));
    mpp.front.contentDisposition.params.popFront();
    assert(mpp.front.contentDisposition.params.empty);
    assert(mpp.front.data == "hello");

    mpp.popFront();
    assert(!mpp.empty);
    assert(mpp.front.contentDisposition.main == "form-data");
    assert(!mpp.front.contentDisposition.params.empty);
    assert(mpp.front.contentDisposition.params.front == KeyValuePair("name", "ocean"));
    mpp.front.contentDisposition.params.popFront();
    assert(mpp.front.contentDisposition.params.empty);
    assert(mpp.front.data == "drift");

    mpp.popFront();
    assert(mpp.empty);
}

unittest
{
    // real-world example, data synthesized using Insomnia
    auto mpp = parseMultipart(
        MultiBuffer(
            "--X-INSOMNIA-BOUNDARY"
            ~ "\r\nContent-Disposition: form-data; name=\"message\""
            ~ "\r\n"
            ~ "\r\nhello"
            ~ "\r\n--X-INSOMNIA-BOUNDARY"
            ~ "\r\nContent-Disposition: form-data; name=\"snow\""
            ~ "\r\n"
            ~ "\r\ncat"
            ~ "\r\n--X-INSOMNIA-BOUNDARY"
            ~ "\r\nContent-Disposition: form-data; name=\"files\"; filename=\"multipart.d\""
            ~ "\r\nContent-Type: application/octet-stream"
            ~ "\r\n"
            ~ "\r\n/++"
            ~ "\n    Multipart data handling"
            ~ "\n +/"
            ~ "\nmodule oceandrift.http.microframework.multipart;"
            ~ "\n"
            ~ "\n@safe pure nothrow:"
            ~ "\n"
            ~ "\nprivate"
            ~ "\n{"
            ~ "\n    enum delimiterPrefix = \"\\r\\n--\";"
            ~ "\n    enum crlf = \"\\r\\n\";"
            ~ "\n}"
            ~ "\n"
            ~ "\r\n--X-INSOMNIA-BOUNDARY"
            ~ "\r\nContent-Disposition: form-data; name=\"files\"; filename=\"hparser.d\""
            ~ "\r\nContent-Type: application/octet-stream"
            ~ "\r\n"
            ~ "\r\n/++"
            ~ "\n    Universal header parser"
            ~ "\n"
            ~ "\n    Designed for multipart files."
            ~ "\n"
            ~ "\n    Supported format:"
            ~ "\n    ---"
            ~ "\n    <Key>: <main-value>; <param1>; <param2>; <param3>; …"
            ~ "\n    ---"
            ~ "\n +/"
            ~ "\nmodule oceandrift.http.microframework.hparser;"
            ~ "\n"
            ~ "\nimport oceandrift.http.message : hstring;"
            ~ "\nimport oceandrift.http.microframework.kvp;"
            ~ "\nimport std.string : indexOf, strip;"
            ~ "\n"
            ~ "\n@safe pure nothrow @nogc:"
            ~ "\n"
            ~ "\nstruct HeaderValue"
            ~ "\n{"
            ~ "\n    hstring main;"
            ~ "\n    HeaderValueParamsParser params;"
            ~ "\n}"
            ~ "\n"
            ~ "\r\n--X-INSOMNIA-BOUNDARY--"
            ~ "\r\n"),
        "X-INSOMNIA-BOUNDARY"
    );

    assert(!mpp.empty);

    assert(mpp.front.contentDisposition.main == "form-data");
    assert(!mpp.front.contentDisposition.params.empty);
    assert(mpp.front.contentDisposition.params.front == KeyValuePair("name", "message"));
    assert(mpp.front.data == "hello");

    mpp.popFront();
    assert(!mpp.empty);
    assert(mpp.front.contentDisposition.main == "form-data");
    assert(!mpp.front.contentDisposition.params.empty);
    assert(mpp.front.contentDisposition.params.front == KeyValuePair("name", "snow"));
    assert(mpp.front.data == "cat");

    mpp.popFront();
    assert(!mpp.empty);
    assert(mpp.front.contentDisposition.main == "form-data");
    assert(!mpp.front.contentDisposition.params.empty);
    assert(mpp.front.contentDisposition.params.front == KeyValuePair("name", "files"));
    mpp.front.contentDisposition.params.popFront();
    assert(!mpp.front.contentDisposition.params.empty);
    assert(mpp.front.contentDisposition.params.front == KeyValuePair("filename", "multipart.d"));
    assert(mpp.front.contentType.main == "application/octet-stream");
    assert(mpp.front.contentType.params.empty);
    assert(mpp.front.data.length == 180);

    mpp.popFront();
    assert(!mpp.empty);
    assert(mpp.front.contentDisposition.main == "form-data");
    assert(!mpp.front.contentDisposition.params.empty);
    assert(mpp.front.contentDisposition.params.front == KeyValuePair("name", "files"));
    mpp.front.contentDisposition.params.popFront();
    assert(!mpp.front.contentDisposition.params.empty);
    assert(mpp.front.contentDisposition.params.front == KeyValuePair("filename", "hparser.d"));
    assert(mpp.front.contentType.main == "application/octet-stream");
    assert(mpp.front.contentType.params.empty);
    assert(mpp.front.data.length == 443);

    mpp.popFront();
    assert(mpp.empty);
}

unittest
{
    // dfmt off
    auto mpp = parseMultipart(
        MultiBuffer(cast(hbuffer)[
                0x2D, 0x2D, 0x58, 0x2D, 0x49, 0x4E, 0x53, 0x4F, 0x4D, 0x4E, 0x49,
                0x41, 0x2D, 0x42, 0x4F, 0x55, 0x4E, 0x44, 0x41, 0x52, 0x59, 0x0D,
                0x0A, 0x43, 0x6F, 0x6E, 0x74, 0x65, 0x6E, 0x74, 0x2D, 0x44, 0x69,
                0x73, 0x70, 0x6F, 0x73, 0x69, 0x74, 0x69, 0x6F, 0x6E, 0x3A, 0x20,
                0x66, 0x6F, 0x72, 0x6D, 0x2D, 0x64, 0x61, 0x74, 0x61, 0x3B, 0x20,
                0x6E, 0x61, 0x6D, 0x65, 0x3D, 0x22, 0x61, 0x76, 0x61, 0x74, 0x61,
                0x72, 0x22, 0x3B, 0x20, 0x66, 0x69, 0x6C, 0x65, 0x6E, 0x61, 0x6D,
                0x65, 0x3D, 0x22, 0x49, 0x4D, 0x47, 0x2D, 0x31, 0x32, 0x33, 0x34,
                0x2E, 0x70, 0x6E, 0x67, 0x22, 0x0D, 0x0A, 0x43, 0x6F, 0x6E, 0x74,
                0x65, 0x6E, 0x74, 0x2D, 0x54, 0x79, 0x70, 0x65, 0x3A, 0x20, 0x69,
                0x6D, 0x61, 0x67, 0x65, 0x2F, 0x70, 0x6E, 0x67, 0x0D, 0x0A, 0x0D,
                0x0A, 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00,
                0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x20, 0x00,
                0x00, 0x00, 0x20, 0x08, 0x03, 0x00, 0x00, 0x00, 0x44, 0xA4, 0x8A,
                0xC6, 0x00, 0x00, 0x00, 0x0F, 0x50, 0x4C, 0x54, 0x45, 0xF3, 0xFA,
                0x04, 0x08, 0x12, 0xF9, 0x10, 0xF9, 0x50, 0x11, 0x14, 0x13, 0xFB,
                0x0E, 0x06, 0xCF, 0xF3, 0x4F, 0xCE, 0x00, 0x00, 0x00, 0x5B, 0x49,
                0x44, 0x41, 0x54, 0x78, 0xDA, 0xC4, 0xCC, 0xD5, 0x15, 0xC3, 0x00,
                0x14, 0xC3, 0x50, 0x3F, 0xD8, 0x7F, 0xE5, 0x36, 0xAC, 0x30, 0x83,
                0x7E, 0x7D, 0x8F, 0x95, 0xA3, 0x7C, 0xD4, 0x17, 0x20, 0x36, 0x80,
                0x8A, 0x96, 0x81, 0xBA, 0xE6, 0x81, 0x44, 0x00, 0xB3, 0x60, 0x17,
                0x01, 0xAA, 0xD8, 0x11, 0x80, 0x2A, 0x1D, 0x06, 0x3A, 0x08, 0x7C,
                0x0B, 0xE8, 0xF2, 0x83, 0x9D, 0x00, 0x31, 0x04, 0x3E, 0xD9, 0xCB,
                0x00, 0x5C, 0x00, 0xAA, 0x00, 0x31, 0xDD, 0x01, 0x08, 0x76, 0x00,
                0x8D, 0x76, 0x00, 0x31, 0x03, 0x26, 0x45, 0xFC, 0x37, 0x02, 0x15,
                0x00, 0x00, 0x8B, 0xB5, 0x06, 0x72, 0xC7, 0xC8, 0xF5, 0x43, 0x00,
                0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
                0x0D, 0x0A, 0x2D, 0x2D, 0x58, 0x2D, 0x49, 0x4E, 0x53, 0x4F, 0x4D,
                0x4E, 0x49, 0x41, 0x2D, 0x42, 0x4F, 0x55, 0x4E, 0x44, 0x41, 0x52,
                0x59, 0x2D, 0x2D, 0x0D, 0x0A,
            ]),
        "X-INSOMNIA-BOUNDARY"
    );
    // dfmt on

    assert(!mpp.empty);
    assert(mpp.front.contentDisposition.main == "form-data");
    assert(!mpp.front.contentDisposition.params.empty);
    assert(mpp.front.contentDisposition.params.front == KeyValuePair("name", "avatar"));
    mpp.front.contentDisposition.params.popFront();
    assert(!mpp.front.contentDisposition.params.empty);
    assert(mpp.front.contentDisposition.params.front == KeyValuePair("filename", "IMG-1234.png"));
    assert(mpp.front.contentType.main == "image/png");
    assert(mpp.front.contentType.params.empty);
    assert(mpp.front.data.length == 175);

    mpp.popFront();
    assert(mpp.empty);
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

    ref MultipartFile front() return @nogc
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

        if (!_data.popCompare(_boundary.data)) // invalid?
        {
            _empty = true;
            return;
        }

        popFront();
    }

    void popFront()
    {
        // after the boundary there should be a linebreak
        if (!_data.popCompare(crlf)) // invalid?
        {
            _empty = true;
            return;
        }

        _front = MultipartFile(); // parse header
        auto headers = parseHeaderBlock(_data);
        while (
            !headers.empty)
        {
            // process header
            enum lctCD = LowerCaseToken.makeConverted(
                    "Content-Disposition");
            enum lctCT = LowerCaseToken.makeConverted(
                    "Content-Type");
            enum lctCTE = LowerCaseToken.makeConverted(
                    "Content-Transfer-Encoding");
            if (equalsCaseInsensitive(headers.front.name, lctCD))
                _front
                    .contentDisposition = headers
                    .front.value;
            else if (
                equalsCaseInsensitive(headers.front.name, lctCT))
                _front
                    .contentType = headers.front.value;
            else if (equalsCaseInsensitive(headers.front.name, lctCTE))
                _front
                    .contentTransferEncoding = headers
                    .front.value;
            headers.popFront();
        }

        // pop header
        foreach (idx; 0 .. headers.bytesRead)
            _data.popFront(); // determine end of body

        immutable ptrdiff_t idxEndOfBody = _data.countUntil(
            (cast(const(ubyte)[]) delimiterPrefix)
                .chain(cast(const(ubyte)[])(_boundary.data))
        );

        // no end marker?
        if (idxEndOfBody < 0)
        {
            // faulty data
            return this.markEndOfData();
        }

        // store body data
        _front.data = _data[0 .. idxEndOfBody];

        // determine how many bytes to skip (body + next delimiter), then skip
        immutable bytesToSkip = idxEndOfBody + delimiterPrefix.length + _boundary
            .length;
        foreach (idx; 0 .. bytesToSkip)
            _data.popFront(); // nothing left?
        if (_data.empty) // faulty
            return this.markEndOfData(); // potential end of data?
        if (_data.front == '-')
        {
            _data.popFront(); // faulty?
            if (_data.empty)
                return this.markEndOfData(); // end of data?
            if (_data.front == '-')
            {
                _data.popFront(); // prepare clean exit

                // There should be a final CRLF,
                // but at this point it doesn’t really matter whether the data is conformant.
                // So, just replace the View (if it’s not already empty).
                if (!_data.empty)
                    _data = MultiBufferView();
            }
        }
    }

    private void markEndOfData() @nogc
    {
        _empty = true;
    }
}

private hstring parseMultipartHeaderValue(
    hbuffer raw, size_t sep) @nogc
{
    immutable size_t offset = (raw[sep + 1] == ' ') ? sep + 2 : sep + 1; // skip ": " separator (quirks support: ":")
    return cast(hstring) raw[offset .. $];
}

private hstring nameFromContentDisposition(
    hstring contentDisposition) @nogc
{
    import oceandrift.http.microframework.hparser : parseHeaderValue;

    foreach (KeyValuePair param; parseHeaderValue(
            contentDisposition).params)
        if (param.key == "name")
            return param.value;
    return hstring(null);
}

hstring determineMultipartBoundary(const hstring contentType) @nogc
{
    import oceandrift.http.microframework.hparser : parseHeaderValue;

    foreach (param; parseHeaderValue(contentType).params)
        if (param.key == "boundary")
            return param.value;
    return hstring(null);
}

hstring determineMultipartBoundary(const const(char)[] contentType) @nogc
{
    return determineMultipartBoundary(hstring(contentType));
}

unittest
{
    assert(determineMultipartBoundary(
            `multipart/form-data; boundary=something`) == "something");
    assert(determineMultipartBoundary(
            `multipart/form-data; boundary=something `) == "something");
    assert(determineMultipartBoundary(
            `multipart/form-data; boundary="something"`) == "something");
    assert(determineMultipartBoundary(
            `multipart/form-data; hosntial=gatsch; boundary="something"`) == "something");
    assert(determineMultipartBoundary(
            `multipart/form-data; boundary="something" `) == "something");
    assert(determineMultipartBoundary(
            `multipart/form-data; boundary="something" z4`) == "something");
    assert(determineMultipartBoundary(
            `multipart/form-data; oachkatzl=schwoaf boundary="something"`).data is null);
    assert(determineMultipartBoundary(
            `multipart/form-data; boundary="something" oachkatzl="schwoaf"`) == "something");
    assert(determineMultipartBoundary(
            `multipart/form-data;oachkatzl="schwoaf"`).data is null);
    assert(determineMultipartBoundary(
            `multipart/form-data;oachkatzl=schwoaf;party`).data is null);
    assert(determineMultipartBoundary(
            `multipart/form-data;boundary="some;thing"`) == "some;thing");
    assert(determineMultipartBoundary(
            `multipart/form-data;boundary=some0thing;party`) == "some0thing");
    assert(determineMultipartBoundary(
            `boundary=_1234_`).data is null);
    assert(determineMultipartBoundary(
            `multipart/form-data; boundary=----z-1234`) == "----z-1234");
    assert(determineMultipartBoundary(
            `multipart/form-data; boundary="----z-1234"`) == "----z-1234");
    assert(determineMultipartBoundary(
            `multipart/form-data; coboundary=b0undary`).data is null);
    assert(determineMultipartBoundary(
            `multipart/form-data; coboundary=b0undary; boundary="boundary"`) == "boundary");
    assert(determineMultipartBoundary(
            `multipart/form-data; garbage="a=b boundary=xyz"; boundary="sth"`) == "sth");
}
