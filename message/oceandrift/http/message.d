/++
    HTTP Message abstraction and representation

    This module’s design was inspired by “PSR-7: HTTP message interfaces”
    created by the PHP Framework Interoperability Group.

    See_Also:
    $(LIST
        * https://www.php-fig.org/psr/psr-7/
    )
+/
module oceandrift.http.message;

import std.traits : ReturnType;

@safe pure:

/++
    Case-insensitive ASCII-string comparision
 +/
bool equalsCaseInsensitive(hstring a, hstring b) pure nothrow
{
    import std.ascii : toLower;

    if (a.length != b.length)
        return false;

    foreach (size_t i, char c; a)
        if (c != b[i])
            if (c.toLower != b[i].toLower)
                return false;

    return true;
}

package(oceandrift.http) struct RequestTransformer
{
@safe pure nothrow:

    private
    {
        Request _msg;
    }

    void reset()
    {
        _msg = Request.init;
        this.setup();
    }

    void setup()
    {
        // Reserve capacity for a few headers.
        // My browser (Firefox 105.0) appears to send less than 16 header lines usually.
        _msg._headers.reserve(20);
    }

    Request getData()
    {
        return _msg;
    }

    void onMethod(const(char)[] method)
    {
        _msg._method = method;
    }

    void onUri(const(char)[] uri)
    {
        _msg._uri = uri;
    }

    void onVersion(const(char)[] protocol)
    {
        _msg._protocol = protocol;
    }

    void onHeader(const(char)[] name, const(char)[] value)
    {
        _msg._headers.append(name, value);
    }

    void onBody(MultiBuffer body)
    {
        _msg._body = body;
    }
}

/++
    “HTTP message string” – short-hand for `const(char)[]``.

    $(SIDEBAR
        Not sure about the name.
        Would have prefered *cstring* (*const string* as opposed to D’s default immutable one),
        but the common association with that term would be “zero-terminated string (as made famous by C)”.
    )
 +/
alias hstring = const(char)[];

public @safe pure nothrow @nogc
{
    /// Emulate input range
    char front(const hstring s)
    {
        return s[0];
    }

    /// ditto
    bool empty(const hstring s)
    {
        return (s.length == 0);
    }

    /// ditto
    void popFront(ref hstring s)
    {
        s = s[1 .. $];
    }
}

/++
    Lower-case HTTP token (tchar string)

    See_Also:
        https://www.rfc-editor.org/rfc/rfc9110#name-tokens
 +/
struct LowerCaseToken
{
@safe pure:

    static class LCTException : Exception
    {
    @nogc @safe pure nothrow:
        this(string msg, string file = __FILE__, size_t line = __LINE__)
        {
            super(msg, file, line);
        }
    }

    private
    {
        const(char)[] _data;
    }

    @disable this();

    private this(const(char)[] data) nothrow @nogc
    {
        _data = data;
    }

    hstring data() const nothrow @nogc
    {
        return _data;
    }

static:
    ///
    LowerCaseToken makeValidated(hstring input)
    {
        import std.ascii : isUpper;
        import std.format;

        foreach (size_t i, const char c; input)
            if (!c.isTChar || c.isUpper)
                throw new LCTException(format!"Invalid tchar(x%X) @%u"(c, i));

        return LowerCaseToken(input);
    }

    ///
    LowerCaseToken makeConverted(hstring input)
    {
        import std.ascii : toLower;
        import std.format;

        auto data = new char[](input.length);

        foreach (size_t i, const char c; input)
            if (c.isTChar)
                data[i] = c.toLower;
            else
                throw new LCTException(format!"Invalid tchar(x%X) @%u"(c, i));

        return LowerCaseToken(data);
    }

    ///
    LowerCaseToken makeSanitized(hstring input) nothrow
    {
        import std.ascii : toLower;

        auto data = new char[](input.length);

        foreach (size_t i, const char c; input)
            data[i] = (c.isTChar) ? c.toLower : '_';

        return LowerCaseToken(data);
    }

    ///
    LowerCaseToken makeAsIs(hstring input) nothrow @nogc
    in
    {
        import std.ascii : isUpper;

        foreach (size_t i, const char c; input)
            assert((c.isTChar && c.isUpper), "Invalid tchar encountered");
    }
    do
    {
        return LowerCaseToken(input);
    }
}

bool equalsCaseInsensitive(const hstring a, const LowerCaseToken b) pure nothrow @nogc
{
    import std.ascii : toLower;

    if (a.length != b.data.length)
        return false;

    foreach (size_t i, const char c; b.data)
        if (c != a[i])
            if (c != a[i].toLower)
                return false;

    return true;
}

bool equalsCaseInsensitive(const const(ubyte)[] a, const LowerCaseToken b) pure nothrow @nogc
{
    return equalsCaseInsensitive(cast(hstring) a, b);
}

unittest
{
    import std.exception;

    assertNotThrown(LowerCaseToken.makeValidated("asdf"));
    assertThrown(LowerCaseToken.makeValidated("ASDF"));
    assertThrown(LowerCaseToken.makeValidated("{asdf}"));
    assertThrown(LowerCaseToken.makeValidated("A-a"));
    assertNotThrown(LowerCaseToken.makeValidated("as-df"));

    assert(LowerCaseToken.makeSanitized("asdf").data == "asdf");
    assert(LowerCaseToken.makeSanitized("ASDF").data == "asdf");
    assert(LowerCaseToken.makeSanitized("{asdf}").data == "_asdf_");
    assert(LowerCaseToken.makeSanitized("A-a").data == "a-a");
    assert(LowerCaseToken.makeSanitized("as-df").data == "as-df");
}

///
struct Header
{
@safe pure nothrow @nogc:

    hstring name;
    hstring[] values;

    bool isSet() const
    {
        return (values.length > 0);
    }
}

private struct Headers
{
@safe pure nothrow:

    private
    {
        Header[] _h;
    }

    void reserve(size_t n)
    {
        this._h.reserve(n);
    }

    void append(LowerCaseToken name, hstring value)
    {
        // search for an existing entry
        foreach (ref header; _h)
        {
            if (header.name.equalsCaseInsensitive(name))
            {
                // found: append value
                header.values ~= value;
                return;
            }
        }

        // new entry
        _h ~= Header(name.data, [value]);
    }

    void append(hstring name, hstring value)
    {
        // search for an existing entry
        foreach (ref header; _h)
        {
            if (header.name.equalsCaseInsensitive(name))
            {
                // found: append value
                header.values ~= value;
                return;
            }
        }

        // new entry
        _h ~= Header(name, [value]);
    }

    void set(LowerCaseToken name, hstring[] values)
    {
        foreach (ref header; _h)
        {
            if (header.name.equalsCaseInsensitive(name))
            {
                // found: override value
                header.values = values;
                return;
            }
        }

        // new entry
        _h ~= Header(name.data, values);
    }

    void set(LowerCaseToken name, hstring value)
    {
        this.set(name, [value]);
    }

    void remove(LowerCaseToken name)
    {
        import std.algorithm : remove;

        _h = _h.remove!(h => h.name.equalsCaseInsensitive(name))();
    }

@nogc:
    bool opBinaryRight(string op : "in")(LowerCaseToken name)
    {
        foreach (header; _h)
            if (header.name.equalsCaseInsensitive(name))
                return true;

        return false;
    }

    Header opIndex(LowerCaseToken name)
    {
        foreach (header; _h)
            if (header.name.equalsCaseInsensitive(name))
                return header;

        return Header(name.data, []);
    }
}

unittest
{
    auto headers = Headers();
    headers.append("Host", "www.dlang.org");
    headers.append("X-Anything", "asdf");
    headers.append("X-anything", "jklö");

    assert(LowerCaseToken.makeConverted("Host") in headers);
    assert(LowerCaseToken.makeConverted("host") in headers);
    assert(
        headers[LowerCaseToken.makeConverted("Host")].values
            == ["www.dlang.org"]
    );

    assert(LowerCaseToken.makeConverted("x-Anything") in headers);
    assert(headers[LowerCaseToken.makeConverted("x-anything")].values[0] == "asdf");
    assert(headers[LowerCaseToken.makeConverted("x-anything")].values[1] == "jklö");

    headers.remove(LowerCaseToken.makeConverted("host"));
    assert(LowerCaseToken.makeConverted("Host") !in headers);
}

/++
    Representation of common parts of HTTP requests and responses

    Standards:
        $(LIST
            * http://www.ietf.org/rfc/rfc7230.txt
            * http://www.ietf.org/rfc/rfc7231.txt
        )
+/
mixin template _Message(TMessage)
{
@safe pure nothrow:

    private
    {
        hstring _protocol = "1.1";
        Headers _headers;
        MultiBuffer _body;
    }

    /++
        Used HTTP protocol version

        Returns:
            The protocol version as a string, e.g. "1.1" or "1.0"
     +/
    hstring protocol() const
    {
        return _protocol;
    }

    /++
        Sets the protocol version

        Returns:
            A new Message with the updated property
     +/
    TMessage withProtocol(hstring protocol)
    {
        TMessage m = this;
        m._protocol = protocol;
        return this;
    }

    /++
        Retrieves all headers of the message
     +/
    Header[] headers()
    {
        return this._headers._h;
    }

    /++
        Determines whether a header exists by the given name.

        ---
        if (requestOrResponse.hasHeader!"Content-Type") {
            // …
        }
        ---
     +/
    bool hasHeader(LowerCaseToken name)
    {
        return (name in _headers);
    }

    /// ditto
    bool hasHeader(hstring name)()
    {
        enum token = LowerCaseToken.makeConverted(name);
        return this.hasHeader(token);
    }

    /++
        Retrieve a specific header’s values by the given name
        ---
        hstring[] accept = requestOrResponse.getHeader!"Accept";
        ---
     +/
    hstring[] getHeader(LowerCaseToken name)
    {
        return _headers[name].values;
    }

    /// ditto
    hstring[] getHeader(hstring name)()
    {
        enum token = LowerCaseToken.makeConverted(name);
        return this.getHeader(token);
    }

    /++
        Sets the header with the specified name to the specified value(s)

        Returns:
            A new Message with the updated property

        ---
        // single value
        response = response.withHeader!"Content-Type"("text/plain");

        // multiple values
        response = response.withHeader!"Access-Control-Allow-Headers"(["content-type", "authorization"]);
        ---

        See_Also:
            [withAddedHeader]
     +/
    TMessage withHeader(LowerCaseToken name, hstring value)
    {
        TMessage m = this;
        m._headers.set(name, value);
        return m;
    }

    /// ditto
    TMessage withHeader(hstring name)(hstring value)
    {
        enum token = LowerCaseToken.makeConverted(name);
        return this.withHeader(token, value);
    }

    /// ditto
    TMessage withHeader(LowerCaseToken name, hstring[] values)
    {
        TMessage m = this;
        m._headers.set(name, values);
        return m;
    }

    /// ditto
    TMessage withHeader(hstring name)(hstring[] values)
    {
        enum token = LowerCaseToken.makeConverted(name);
        return this.withHeader(token, values);
    }

    /++
        Appends the given value to the specified header

        Returns:
            A new Message with the updated property

        ---
        response = response.withHeader!"Cache-Control"("no-cache"); // overrides existing any values

        response = response.withAddedHeader!"Cache-Control"("no-store"); // appends the new value

        response = response.withAddedHeader!"Cache-Control"([
            "private",
            "must-revalidate",
        ]); // appends the new values
        ---
     +/
    TMessage withAddedHeader(LowerCaseToken name, hstring value)
    {
        TMessage m = this;
        m._headers.append(name, value);
        return m;
    }

    /// ditto
    TMessage withAddedHeader(hstring name)(hstring value)
    {
        enum token = LowerCaseToken.makeConverted(name);
        return this.withAddedHeader(token, value);
    }

    /++
        Removes the specified header from a message

        Returns:
            A new Message with the updated property

        ---
        // e.g. remove cookies from the response
        response = response.withoutHeader!"Set-Cookie"();
        ---
     +/
    TMessage withoutHeader(LowerCaseToken name)
    {
        TMessage m = this;
        m._headers.remove(name);
        return m;
    }

    /// ditto
    TMessage withoutHeader(hstring name)()
    {
        enum token = LowerCaseToken.makeConverted(name);
        return this.withoutHeader(token);
    }

    /++
        Gets the body of the message
     +/
    ref MultiBuffer body_() return
    {
        return _body;
    }

    /++
        Replaces the body of a message

        Returns:
            A new Message with the updated property
     +/
    TMessage withBody(MultiBuffer body_)
    {
        TMessage m = this;
        m._body = body_;
        return m;
    }
}

/++
    Representation of an HTTP request
 +/
mixin template _Request(TRequest)
{
@safe pure nothrow:

    mixin _Message!TRequest;

    private
    {
        hstring _method;
        hstring _uri;
    }

    /++
        Request method

        Returns:
            The request method as a string (e.g. "GET", "POST", "HEAD")
     +/
    hstring method() const
    {
        return _method;
    }

    /++
        Replaces the request method of the request
     +/
    TRequest withMethod(hstring method)
    {
        TRequest r = this;
        r._method = method;
        return r;
    }

    /++
        Request URI

        Path + Query string (no host, no protocol),
        e.g. "/hello-world?foo=bar"
     +/
    hstring uri() const
    {
        return _uri;
    }

    /++
        Sets the URI of the request

        Returns:
            A new Request with the updated property

        ---
        request = request.withUri("/new-uri");
        ---
     +/
    TRequest withUri(hstring uri)
    {
        TRequest r = this;
        r._uri = uri;
        return r;
    }
}

/++
    Representation of an HTTP response
 +/
mixin template _Response(TResponse)
{
@safe pure nothrow:

    mixin _Message!TResponse;

    private
    {
        int _statusCode = 200;
        hstring _reasonPhrase = "OK";
    }

    /++
        HTTP response status code
     +/
    int statusCode() const
    {
        return _statusCode;
    }

    /++
        Sets the response’s HTTP status code

        Returns:
            A new Response with the updated property

        ---
        response = response.withStatus(404);

        // optionally with a custom reason-phrase
        response = response.withStatus(404, "Not Found");
        ---
     +/
    TResponse withStatus(int code, hstring reasonPhrase = null)
    {
        TResponse r = this;
        r._statusCode = code;
        r._reasonPhrase = reasonPhrase;
        return r;
    }

    /++
        Reason phrase of the response

        Might not be set (i.e. null)
     +/
    public hstring reasonPhrase()
    {
        return _reasonPhrase;
    }
}

/++
    HTTP request representation
 +/
struct Request
{
    mixin _Request!Request;
}

/++
    HTTP response representation
 +/
struct Response
{
    mixin _Response!Response;

    this(int statusCode, hstring reasonPhrase = null)
    {
        this._statusCode = statusCode;
        this._reasonPhrase = reasonPhrase;
    }
}

/// https://www.iana.org/assignments/http-status-codes/http-status-codes.xhtml
enum string[int] reasonPhrase = [
        100: "Continue", // [RFC9110, Section 15.2.1]
        101: "Switching Protocols", // [RFC9110, Section 15.2.2]
        102: "Processing", // [RFC2518]
        103: "Early Hints", // [RFC8297]

        200: "OK", // [RFC9110, Section 15.3.1]
        201: "Created", // [RFC9110, Section 15.3.2]
        202: "Accepted", // [RFC9110, Section 15.3.3]
        203: "Non-Authoritative Information", // [RFC9110, Section 15.3.4]
        204: "No Content", // [RFC9110, Section 15.3.5]
        205: "Reset Content", // [RFC9110, Section 15.3.6]
        206: "Partial Content", // [RFC9110, Section 15.3.7]
        207: "Multi-Status", // [RFC4918]
        208: "Already Reported", // [RFC5842]
        226: "IM Used", // [RFC3229]

        300: "Multiple Choices", // [RFC9110, Section 15.4.1]
        301: "Moved Permanently", // [RFC9110, Section 15.4.2]
        302: "Found", // [RFC9110, Section 15.4.3]
        303: "See Other", // [RFC9110, Section 15.4.4]
        304: "Not Modified", // [RFC9110, Section 15.4.5]
        305: "Use Proxy", // [RFC9110, Section 15.4.6]
        306: "(Unused)", // [RFC9110, Section 15.4.7]
        307: "Temporary Redirect", // [RFC9110, Section 15.4.8]
        308: "Permanent Redirect", // [RFC9110, Section 15.4.9]

        400: "Bad Request", // [RFC9110, Section 15.5.1]
        401: "Unauthorized", // [RFC9110, Section 15.5.2]
        402: "Payment Required", // [RFC9110, Section 15.5.3]
        403: "Forbidden", // [RFC9110, Section 15.5.4]
        404: "Not Found", // [RFC9110, Section 15.5.5]
        405: "Method Not Allowed", // [RFC9110, Section 15.5.6]
        406: "Not Acceptable", // [RFC9110, Section 15.5.7]
        407: "Proxy Authentication Required", // [RFC9110, Section 15.5.8]
        408: "Request Timeout", // [RFC9110, Section 15.5.9]
        409: "Conflict", // [RFC9110, Section 15.5.10]
        410: "Gone", // [RFC9110, Section 15.5.11]
        411: "Length Required", // [RFC9110, Section 15.5.12]
        412: "Precondition Failed", // [RFC9110, Section 15.5.13]
        413: "Content Too Large", // [RFC9110, Section 15.5.14]
        414: "URI Too Long", // [RFC9110, Section 15.5.15]
        415: "Unsupported Media Type", // [RFC9110, Section 15.5.16]
        416: "Range Not Satisfiable", // [RFC9110, Section 15.5.17]
        417: "Expectation Failed", // [RFC9110, Section 15.5.18]
        418: "I'm a teapot", // [RFC9110, Section 15.5.19] [see also: RFC2324]
        421: "Misdirected Request", // [RFC9110, Section 15.5.20]
        422: "Unprocessable Content", // [RFC9110, Section 15.5.21]
        423: "Locked", // [RFC4918]
        424: "Failed Dependency", // [RFC4918]
        425: "Too Early", // [RFC8470]
        426: "Upgrade Required", // [RFC9110, Section 15.5.22]
        428: "Precondition Required", // [RFC6585]
        429: "Too Many Requests", // [RFC6585]
        431: "Request Header Fields Too Large", // [RFC6585]
        451: "Unavailable For Legal Reasons", // [RFC7725]

        500: "Internal Server Error", // [RFC9110, Section 15.6.1]
        501: "Not Implemented", // [RFC9110, Section 15.6.2]
        502: "Bad Gateway", // [RFC9110, Section 15.6.3]
        503: "Service Unavailable", // [RFC9110, Section 15.6.4]
        504: "Gateway Timeout", // [RFC9110, Section 15.6.5]
        505: "HTTP Version Not Supported", // [RFC9110, Section 15.6.6]
        506: "Variant Also Negotiates", // [RFC2295]
        507: "Insufficient Storage", // [RFC4918]
        508: "Loop Detected", // [RFC5842]
        510: "Not Extended", // [RFC2774][status-change-http-experiments-to-historic]
        511: "Network Authentication Required", // [RFC6585]
    ];

string getReasonPhrase(int status) pure nothrow @nogc
{
    switch (status)
    {
        static foreach (sc, rp; reasonPhrase)
    case sc:
            return rp;

    default:
        if (status <= 99)
            return "Whatever";
        if (status <= 199)
            return "Informational";
        if (status <= 299)
            return "Successful";
        if (status <= 399)
            return "Redirection";
        if (status <= 499)
            return "Client error";
        if (status < 599)
            return "Server error";
        return "Whatever";
    }
}

bool isTChar(const char c) pure nothrow @nogc
{
    import std.ascii : isGraphical;

    if (!c.isGraphical)
        return false;

    // Delimiters are chosen from the set of US-ASCII visual characters not allowed in a token (DQUOTE and "(),/:;<=>?@[\]{}").

    // dfmt off
        if (
                (c == 34)               // '"'
            ||  (c == 40)               // '('
            ||  (c == 41)               // ')'
            ||  (c == 44)               // ','
            ||  (c == 47)               // '/'
            || ((c >= 58) && (c <= 64)) // 58 == ':', 59 == ';', 60 == '<', 61 == '=', 62 == '>', 63 == '?', 64 == '@'
            || ((c >= 91) && (c <= 93)) // 91 == '[', 92 == '\', 93 == ']'
            ||  (c == 123)              // '{'
            ||  (c == 125)              // '}'
        ) {
            return false;
        }
        // dfmt on

    return true;
}

///
alias hbuffer = const(ubyte)[];

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
