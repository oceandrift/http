/++
    HTTP Message abstraction

    This work is a derivative work based on “PSR-7: HTTP message interfaces”.
    It features significant changes and is not compatible with the original.

    ---
    Copyright (c) 2014 PHP Framework Interoperability Group

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in
    all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
    THE SOFTWARE.
    ---

    See_Also:
    $(LIST
        * https://www.php-fig.org/psr/psr-7/
        * https://github.com/php-fig/http-message
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

    void onBody(Body body_)
    {
        _msg._body = body_;
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

struct Body
{
@safe pure nothrow:

    import std.array : appender, Appender;
    import std.traits : isIntegral;

    private
    {
        Appender!(const(ubyte)[]) _data;
    }

    const(ubyte)[] data() const
    {
        return _data.data;
    }

    hstring toString() const
    {
        return cast(hstring) _data.data;
    }

    void rewind()
    {
        _data = appender!(const(ubyte)[]);
    }

    void write(const(ubyte)[] data)
    {
        _data.put(data);
    }

    void write(hstring data)
    {
        this.write(cast(const(ubyte)[]) data);
    }

    void write(ubyte c)
    {
        _data.put([c]);
    }

    void write(char c)
    {
        this.write(cast(ubyte) c);
    }

    void write(Integer)(Integer i) if (isIntegral!Integer)
    {
        import std.conv : to;

        this.write(i.to!string);
    }

    void write(Args...)(Args args)
    {
        import std.traits : isArray, Unqual;

        static foreach (a; args)
        {
            {
                alias T = Unqual!(typeof(a));
                static if (isArray!T)
                {
                    {
                        alias TE = Unqual!(typeof(a[0]));
                        static if (is(TE == ubyte))
                            this.write(a);
                        else static if (is(TE == char))
                            this.write(a);
                        else
                            static assert(0, "incompatible array type");
                    }

                }
                else static if (is(T == ubyte))
                    this.write(a);
                else static if (is(T == char))
                    this.write(a);
                else static if (isIntegral!T)
                    this.write(a);
                else
                    static assert(0, "Cannot write element of type `" ~ typeof(a).stringof ~ "`");
            }
        }
    }
}

/**
 * HTTP messages consist of requests from a client to a server and responses
 * from a server to a client. This interface defines the methods common to
 * each.
 *
 * Messages are considered immutable; all methods that might change state MUST
 * be implemented such that they retain the internal state of the current
 * message and return an instance that contains the changed state.
 *
 * @link http://www.ietf.org/rfc/rfc7230.txt
 * @link http://www.ietf.org/rfc/rfc7231.txt
 */
mixin template _Message(TMessage)
{
@safe pure nothrow:

    private
    {
        hstring _protocol;
        Headers _headers;
        Body _body;
    }

    /**
     * Retrieves the HTTP protocol version as a string.
     *
     * The string MUST contain only the HTTP version number (e.g., "1.1", "1.0").
     *
     * @return string HTTP protocol version.
     */
    hstring protocol() const
    {
        return _protocol;
    }

    /**
     * Return an instance with the specified HTTP protocol version.
     *
     * The version string MUST contain only the HTTP version number (e.g.,
     * "1.1", "1.0").
     *
     * This method MUST be implemented in such a way as to retain the
     * immutability of the message, and MUST return an instance that has the
     * new protocol version.
     *
     * @param string $version HTTP protocol version
     * @return static
     */
    TMessage withProtocol(hstring protocol)
    {
        TMessage m = this;
        m._protocol = protocol;
        return this;
    }

    /**
     * Retrieves all message header values.
     *
     * The keys represent the header name as it will be sent over the wire, and
     * each value is an array of strings associated with the header.
     *
     *     // Represent the headers as a string
     *     foreach ($message->getHeaders() as $name => $values) {
     *         echo $name . ": " . implode(", ", $values);
     *     }
     *
     *     // Emit headers iteratively:
     *     foreach ($message->getHeaders() as $name => $values) {
     *         foreach ($values as $value) {
     *             header(sprintf('%s: %s', $name, $value), false);
     *         }
     *     }
     *
     * While header names are not case-sensitive, getHeaders() will preserve the
     * exact case in which headers were originally specified.
     *
     * @return string[][] Returns an associative array of the message's headers. Each
     *     key MUST be a header name, and each value MUST be an array of strings
     *     for that header.
     */
    Header[] headers()
    {
        return this._headers._h;
    }

    /**
     * Checks if a header exists by the given case-insensitive name.
     *
     * @param string $name Case-insensitive header field name.
     * @return bool Returns true if any header names match the given header
     *     name using a case-insensitive string comparison. Returns false if
     *     no matching header name is found in the message.
     */
    bool hasHeader(LowerCaseToken name)
    {
        return (name in _headers);
    }

    bool hasHeader(hstring name)()
    {
        enum token = LowerCaseToken.makeConverted(name);
        return this.hasHeader(token);
    }

    /**
     * Retrieves a message header value by the given case-insensitive name.
     *
     * This method returns an array of all the header values of the given
     * case-insensitive header name.
     *
     * If the header does not appear in the message, this method MUST return an
     * empty array.
     *
     * @param string $name Case-insensitive header field name.
     * @return string[] An array of string values as provided for the given
     *    header. If the header does not appear in the message, this method MUST
     *    return an empty array.
     */
    hstring[] getHeader(LowerCaseToken name)
    {
        return _headers[name].values;
    }

    hstring[] getHeader(hstring name)()
    {
        enum token = LowerCaseToken.makeConverted(name);
        return this.getHeader(token);
    }

    /**
     * Return an instance with the provided value replacing the specified header.
     *
     * While header names are case-insensitive, the casing of the header will
     * be preserved by this function, and returned from getHeaders().
     *
     * This method MUST be implemented in such a way as to retain the
     * immutability of the message, and MUST return an instance that has the
     * new and/or updated header and value.
     *
     * @param string $name Case-insensitive header field name.
     * @param string|string[] $value Header value(s).
     * @return static
     * @throws \InvalidArgumentException for invalid header names or values.
     */
    TMessage withHeader(LowerCaseToken name, hstring value)
    {
        TMessage m = this;
        m._headers.set(name, value);
        return m;
    }

    TMessage withHeader(hstring name)(hstring value)
    {
        enum token = LowerCaseToken.makeConverted(name);
        return this.withHeader(token, value);
    }

    TMessage withHeader(LowerCaseToken name, hstring[] values)
    {
        TMessage m = this;
        m._headers.set(name, values);
        return m;
    }

    /**
     * Return an instance with the specified header appended with the given value.
     *
     * Existing values for the specified header will be maintained. The new
     * value(s) will be appended to the existing list. If the header did not
     * exist previously, it will be added.
     *
     * This method MUST be implemented in such a way as to retain the
     * immutability of the message, and MUST return an instance that has the
     * new header and/or value.
     *
     * @param string $name Case-insensitive header field name to add.
     * @param string|string[] $value Header value(s).
     * @return static
     * @throws \InvalidArgumentException for invalid header names or values.
     */
    TMessage withAddedHeader(hstring name, hstring value)
    {
        TMessage m = this;
        m._headers.append(name, value);
        return m;
    }

    /**
     * Return an instance without the specified header.
     *
     * Header resolution MUST be done without case-sensitivity.
     *
     * This method MUST be implemented in such a way as to retain the
     * immutability of the message, and MUST return an instance that removes
     * the named header.
     *
     * @param string $name Case-insensitive header field name to remove.
     * @return static
     */
    TMessage withoutHeader(LowerCaseToken name)
    {
        TMessage m = this;
        m._headers.remove(name);
        return m;
    }

    /**
     * Gets the body of the message.
     *
     * @return StreamInterface Returns the body as a stream.
     */
    ref Body body_() return
    {
        return _body;
    }

    /**
     * Return an instance with the specified message body.
     *
     * The body MUST be a StreamInterface object.
     *
     * This method MUST be implemented in such a way as to retain the
     * immutability of the message, and MUST return a new instance that has the
     * new body stream.
     *
     * @param StreamInterface $body Body.
     * @return static
     * @throws \InvalidArgumentException When the body is not valid.
     */
    TMessage withBody(Body body_)
    {
        TMessage m = this;
        m._body = body_;
        return m;
    }
}

/**
 * Representation of an outgoing, client-side request.
 *
 * Per the HTTP specification, this interface includes properties for
 * each of the following:
 *
 * - Protocol version
 * - HTTP method
 * - URI
 * - Headers
 * - Message body
 *
 * During construction, implementations MUST attempt to set the Host header from
 * a provided URI if no Host header is provided.
 *
 * Requests are considered immutable; all methods that might change state MUST
 * be implemented such that they retain the internal state of the current
 * message and return an instance that contains the changed state.
 */
mixin template _Request(TRequest)
{
@safe pure nothrow:

    mixin _Message!TRequest;

    private
    {
        hstring _method;
        hstring _uri;
    }

    /**
     * Retrieves the HTTP method of the request.
     *
     * @return string Returns the request method.
     */
    hstring method() const
    {
        return _method;
    }

    /**
     * Return an instance with the provided HTTP method.
     *
     * While HTTP method names are typically all uppercase characters, HTTP
     * method names are case-sensitive and thus implementations SHOULD NOT
     * modify the given string.
     *
     * This method MUST be implemented in such a way as to retain the
     * immutability of the message, and MUST return an instance that has the
     * changed request method.
     *
     * @param string $method Case-sensitive method.
     * @return static
     * @throws \InvalidArgumentException for invalid HTTP methods.
     */
    TRequest withMethod(hstring method)
    {
        TRequest r = this;
        r._method = method;
        return r;
    }

    /**
     * Retrieves the URI instance.
     *
     * This method MUST return a UriInterface instance.
     *
     * @link http://tools.ietf.org/html/rfc3986#section-4.3
     * @return UriInterface Returns a UriInterface instance
     *     representing the URI of the request.
     */
    hstring uri() const
    {
        return _uri;
    }

    /**
     * Returns an instance with the provided URI.
     *
     * This method MUST update the Host header of the returned request by
     * default if the URI contains a host component. If the URI does not
     * contain a host component, any pre-existing Host header MUST be carried
     * over to the returned request.
     *
     * You can opt-in to preserving the original state of the Host header by
     * setting `$preserveHost` to `true`. When `$preserveHost` is set to
     * `true`, this method interacts with the Host header in the following ways:
     *
     * - If the Host header is missing or empty, and the new URI contains
     *   a host component, this method MUST update the Host header in the returned
     *   request.
     * - If the Host header is missing or empty, and the new URI does not contain a
     *   host component, this method MUST NOT update the Host header in the returned
     *   request.
     * - If a Host header is present and non-empty, this method MUST NOT update
     *   the Host header in the returned request.
     *
     * This method MUST be implemented in such a way as to retain the
     * immutability of the message, and MUST return an instance that has the
     * new UriInterface instance.
     *
     * @link http://tools.ietf.org/html/rfc3986#section-4.3
     * @param UriInterface $uri New request URI to use.
     * @param bool $preserveHost Preserve the original state of the Host header.
     * @return static
     */
    TRequest withUri(hstring uri)
    {
        TRequest r = this;
        r._uri = uri;
        return r;
    }
}

/**
 * Representation of an outgoing, server-side response.
 *
 * Per the HTTP specification, this interface includes properties for
 * each of the following:
 *
 * - Protocol version
 * - Status code and reason phrase
 * - Headers
 * - Message body
 *
 * Responses are considered immutable; all methods that might change state MUST
 * be implemented such that they retain the internal state of the current
 * message and return an instance that contains the changed state.
 */
mixin template _Response(TResponse)
{
@safe pure nothrow:

    mixin _Message!TResponse;

    private
    {
        int _statusCode = 200;
        hstring _reasonPhrase = "OK";
    }

    /**
     * Gets the response status code.
     *
     * The status code is a 3-digit integer result code of the server's attempt
     * to understand and satisfy the request.
     *
     * @return int Status code.
     */
    int statusCode() const
    {
        return _statusCode;
    }

    /**
     * Return an instance with the specified status code and, optionally, reason phrase.
     *
     * If no reason phrase is specified, implementations MAY choose to default
     * to the RFC 7231 or IANA recommended reason phrase for the response's
     * status code.
     *
     * This method MUST be implemented in such a way as to retain the
     * immutability of the message, and MUST return an instance that has the
     * updated status and reason phrase.
     *
     * @link http://tools.ietf.org/html/rfc7231#section-6
     * @link http://www.iana.org/assignments/http-status-codes/http-status-codes.xhtml
     * @param int $code The 3-digit integer result code to set.
     * @param string $reasonPhrase The reason phrase to use with the
     *     provided status code; if none is provided, implementations MAY
     *     use the defaults as suggested in the HTTP specification.
     * @return static
     * @throws \InvalidArgumentException For invalid status code arguments.
     */
    TResponse withStatus(int code, hstring reasonPhrase = null)
    {
        TResponse r = this;
        r._statusCode = code;
        r._reasonPhrase = reasonPhrase;
        return r;
    }

    /**
     * Gets the response reason phrase associated with the status code.
     *
     * Because a reason phrase is not a required element in a response
     * status line, the reason phrase value MAY be null. Implementations MAY
     * choose to return the default RFC 7231 recommended reason phrase (or those
     * listed in the IANA HTTP Status Code Registry) for the response's
     * status code.
     *
     * @link http://tools.ietf.org/html/rfc7231#section-6
     * @link http://www.iana.org/assignments/http-status-codes/http-status-codes.xhtml
     * @return string Reason phrase; must return an empty string if none present.
     */
    public hstring reasonPhrase()
    {
        return _reasonPhrase;
    }
}

///
struct Request
{
    mixin _Request!Request;
}

///
struct Response
{
    mixin _Response!Response;
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
