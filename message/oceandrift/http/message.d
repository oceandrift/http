/++
    HTTP Message abstraction

    This work is a derivative work based on “PSR-7: HTTP message interfaces”.
    It features siginificant changes and is not compatible with the original.

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

import std.algorithm : equal;
import std.traits : ReturnType;
import std.uni : asLowerCase;

@safe:

/++
    Case-insensitive ASCII-string comparision
 +/
bool equalCaseInsensitive(hstring a, hstring b) pure
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

unittest
{
    assert(equalCaseInsensitive("a", "a"));
    assert(equalCaseInsensitive("Oachkatzlschwoaf", "OACHKATZLSCHWOAF"));
    assert(equalCaseInsensitive("asdf", "ASDF"));
    assert(equalCaseInsensitive("Keep-Alive", "keep-alive"));
    assert(equalCaseInsensitive("kEEp-aLIVe", "Keep-Alive"));
    assert(equalCaseInsensitive("a", "a"));
    assert(equalCaseInsensitive("a", "a"));
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

    void append(hstring name, hstring value)
    {
        // search for an existing entry
        foreach (ref header; _h)
        {
            if (header.name.asLowerCase.equal(name.asLowerCase))
            {
                // found: append value
                header.values ~= value;
                return;
            }
        }

        // new entry
        _h ~= Header(name, [value]);
    }

    void set(hstring name, hstring[] values)
    {
        foreach (ref header; _h)
        {
            if (header.name.asLowerCase.equal(name.asLowerCase))
            {
                // found: override value
                header.values = values;
                return;
            }
        }

        _h ~= Header(name, values);
    }

    void set(hstring name, hstring value)
    {
        this.set(name, [value]);
    }

    void remove(hstring name)
    {
        import std.algorithm : remove;

        this._h = this._h.remove!(h => h.name.asLowerCase.equal(name.asLowerCase));
    }

@nogc:
    bool opBinaryRight(string op : "in")(hstring name)
    {
        foreach (header; _h)
            if (header.name.asLowerCase.equal(name.asLowerCase))
                return true;

        return false;
    }

    Header opIndex(hstring name)
    {
        foreach (header; _h)
            if (header.name.asLowerCase.equal(name.asLowerCase))
                return header;

        return Header(name, []);
    }
}

unittest
{
    auto headers = Headers();
    headers.append("Host", "www.dlang.org");
    headers.append("X-Anything", "asdf");
    headers.append("X-anything", "jklö");

    assert("Host" in headers);
    assert("host" in headers);
    assert(headers["Host"].values == ["www.dlang.org"]);

    assert("x-Anything" in headers);
    assert(headers["x-anything"].values[0] == "asdf");
    assert(headers["x-anything"].values[1] == "jklö");

    headers.remove("host");
    assert("Host" !in headers);
}

struct Body
{
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
    hstring protocol()
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
    bool hasHeader(hstring name)
    {
        return (name in _headers);
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
    hstring[] getHeader(hstring name)
    {
        return _headers[name].values;
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
    TMessage withHeader(hstring name, hstring value)
    {
        TMessage m = this;
        m._headers.set(name, value);
        return m;
    }

    TMessage withHeader(hstring name, hstring[] values)
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
    TMessage withoutHeader(hstring name)
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
    mixin _Message!TRequest;

    private
    {
        hstring _method;
        hstring _uri;
    }

    /**
     * Retrieves the message's request target.
     *
     * Retrieves the message's request-target either as it will appear (for
     * clients), as it appeared at request (for servers), or as it was
     * specified for the instance (see withRequestTarget()).
     *
     * In most cases, this will be the origin-form of the composed URI,
     * unless a value was provided to the concrete implementation (see
     * withRequestTarget() below).
     *
     * If no URI is available, and no request-target has been specifically
     * provided, this method MUST return the string "/".
     *
     * @return string
     */
    hstring getRequestTarget();

    /**
     * Return an instance with the specific request-target.
     *
     * If the request needs a non-origin-form request-target — e.g., for
     * specifying an absolute-form, authority-form, or asterisk-form —
     * this method may be used to create an instance with the specified
     * request-target, verbatim.
     *
     * This method MUST be implemented in such a way as to retain the
     * immutability of the message, and MUST return an instance that has the
     * changed request target.
     *
     * @link http://tools.ietf.org/html/rfc7230#section-5.3 (for the various
     *     request-target forms allowed in request messages)
     * @param mixed $requestTarget
     * @return static
     */
    TRequest withRequestTarget(hstring requestTarget);

    /**
     * Retrieves the HTTP method of the request.
     *
     * @return string Returns the request method.
     */
    hstring method()
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
    hstring uri()
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
 * Representation of an incoming, server-side HTTP request.
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
 * Additionally, it encapsulates all data as it has arrived to the
 * application from the CGI and/or PHP environment, including:
 *
 * - The values represented in $_SERVER.
 * - Any cookies provided (generally via $_COOKIE)
 * - Query string arguments (generally via $_GET, or as parsed via parse_str())
 * - Upload files, if any (as represented by $_FILES)
 * - Deserialized body parameters (generally from $_POST)
 *
 * $_SERVER values MUST be treated as immutable, as they represent application
 * state at the time of request; as such, no methods are provided to allow
 * modification of those values. The other values provide such methods, as they
 * can be restored from $_SERVER or the request body, and may need treatment
 * during the application (e.g., body parameters may be deserialized based on
 * content type).
 *
 * Additionally, this interface recognizes the utility of introspecting a
 * request to derive and match additional parameters (e.g., via URI path
 * matching, decrypting cookie values, deserializing non-form-encoded body
 * content, matching authorization headers to users, etc). These parameters
 * are stored in an "attributes" property.
 *
 * Requests are considered immutable; all methods that might change state MUST
 * be implemented such that they retain the internal state of the current
 * message and return an instance that contains the changed state.
 */
mixin template _ServerRequest(TRequest)
{
    mixin _Request!TRequest;

    /**
     * Retrieve server parameters.
     *
     * Retrieves data related to the incoming request environment,
     * typically derived from PHP's $_SERVER superglobal. The data IS NOT
     * REQUIRED to originate from $_SERVER.
     *
     * @return array
     */
    string[string] getServerParams();

    /**
     * Retrieve cookies.
     *
     * Retrieves cookies sent by the client to the server.
     *
     * The data MUST be compatible with the structure of the $_COOKIE
     * superglobal.
     *
     * @return array
     */
    string[] getCookieParams();

    /**
     * Return an instance with the specified cookies.
     *
     * The data IS NOT REQUIRED to come from the $_COOKIE superglobal, but MUST
     * be compatible with the structure of $_COOKIE. Typically, this data will
     * be injected at instantiation.
     *
     * This method MUST NOT update the related Cookie header of the request
     * instance, nor related values in the server params.
     *
     * This method MUST be implemented in such a way as to retain the
     * immutability of the message, and MUST return an instance that has the
     * updated cookie values.
     *
     * @param array $cookies Array of key/value pairs representing cookies.
     * @return static
     */
    TRequest withCookieParams(string[] cookies);

    /**
     * Retrieve query string arguments.
     *
     * Retrieves the deserialized query string arguments, if any.
     *
     * Note: the query params might not be in sync with the URI or server
     * params. If you need to ensure you are only getting the original
     * values, you may need to parse the query string from `getUri()->getQuery()`
     * or from the `QUERY_STRING` server param.
     *
     * @return array
     */
    string[] getQueryParams();

    /**
     * Return an instance with the specified query string arguments.
     *
     * These values SHOULD remain immutable over the course of the incoming
     * request. They MAY be injected during instantiation, such as from PHP's
     * $_GET superglobal, or MAY be derived from some other value such as the
     * URI. In cases where the arguments are parsed from the URI, the data
     * MUST be compatible with what PHP's parse_str() would return for
     * purposes of how duplicate query parameters are handled, and how nested
     * sets are handled.
     *
     * Setting query string arguments MUST NOT change the URI stored by the
     * request, nor the values in the server params.
     *
     * This method MUST be implemented in such a way as to retain the
     * immutability of the message, and MUST return an instance that has the
     * updated query string arguments.
     *
     * @param array $query Array of query string arguments, typically from
     *     $_GET.
     * @return static
     */
    TRequest withQueryParams(string[string] query);

    /**
     * Retrieve normalized file upload data.
     *
     * This method returns upload metadata in a normalized tree, with each leaf
     * an instance of Psr\Http\Message\UploadedFileInterface.
     *
     * These values MAY be prepared from $_FILES or the message body during
     * instantiation, or MAY be injected via withUploadedFiles().
     *
     * @return array An array tree of UploadedFileInterface instances; an empty
     *     array MUST be returned if no data is present.
     */
    string[] getUploadedFiles();

    /**
     * Create a new instance with the specified uploaded files.
     *
     * This method MUST be implemented in such a way as to retain the
     * immutability of the message, and MUST return an instance that has the
     * updated body parameters.
     *
     * @param array $uploadedFiles An array tree of UploadedFileInterface instances.
     * @return static
     * @throws \InvalidArgumentException if an invalid structure is provided.
     */
    TRequest withUploadedFiles(string[] uploadedFiles);

    /**
     * Retrieve any parameters provided in the request body.
     *
     * If the request Content-Type is either application/x-www-form-urlencoded
     * or multipart/form-data, and the request method is POST, this method MUST
     * return the contents of $_POST.
     *
     * Otherwise, this method may return any results of deserializing
     * the request body content; as parsing returns structured content, the
     * potential types MUST be arrays or objects only. A null value indicates
     * the absence of body content.
     *
     * @return null|array|object The deserialized body parameters, if any.
     *     These will typically be an array or object.
     */
    Body getParsedBody();

    /**
     * Return an instance with the specified body parameters.
     *
     * These MAY be injected during instantiation.
     *
     * If the request Content-Type is either application/x-www-form-urlencoded
     * or multipart/form-data, and the request method is POST, use this method
     * ONLY to inject the contents of $_POST.
     *
     * The data IS NOT REQUIRED to come from $_POST, but MUST be the results of
     * deserializing the request body content. Deserialization/parsing returns
     * structured data, and, as such, this method ONLY accepts arrays or objects,
     * or a null value if nothing was available to parse.
     *
     * As an example, if content negotiation determines that the request data
     * is a JSON payload, this method could be used to create a request
     * instance with the deserialized parameters.
     *
     * This method MUST be implemented in such a way as to retain the
     * immutability of the message, and MUST return an instance that has the
     * updated body parameters.
     *
     * @param null|array|object $data The deserialized body data. This will
     *     typically be in an array or object.
     * @return static
     * @throws \InvalidArgumentException if an unsupported argument type is
     *     provided.
     */
    TRequest withParsedBody(Body data);

    /**
     * Retrieve attributes derived from the request.
     *
     * The request "attributes" may be used to allow injection of any
     * parameters derived from the request: e.g., the results of path
     * match operations; the results of decrypting cookies; the results of
     * deserializing non-form-encoded message bodies; etc. Attributes
     * will be application and request specific, and CAN be mutable.
     *
     * @return array Attributes derived from the request.
     */
    Object[] getAttributes();

    /**
     * Retrieve a single derived request attribute.
     *
     * Retrieves a single derived request attribute as described in
     * getAttributes(). If the attribute has not been previously set, returns
     * the default value as provided.
     *
     * This method obviates the need for a hasAttribute() method, as it allows
     * specifying a default value to return if the attribute is not found.
     *
     * @see getAttributes()
     * @param string $name The attribute name.
     * @param mixed $default Default value to return if the attribute does not exist.
     * @return mixed
     */
    Object getAttribute(hstring name, Object default_ = null);

    /**
     * Return an instance with the specified derived request attribute.
     *
     * This method allows setting a single derived request attribute as
     * described in getAttributes().
     *
     * This method MUST be implemented in such a way as to retain the
     * immutability of the message, and MUST return an instance that has the
     * updated attribute.
     *
     * @see getAttributes()
     * @param string $name The attribute name.
     * @param mixed $value The value of the attribute.
     * @return static
     */
    TRequest withAttribute(hstring name, Object value);

    /**
     * Return an instance that removes the specified derived request attribute.
     *
     * This method allows removing a single derived request attribute as
     * described in getAttributes().
     *
     * This method MUST be implemented in such a way as to retain the
     * immutability of the message, and MUST return an instance that removes
     * the attribute.
     *
     * @see getAttributes()
     * @param string $name The attribute name.
     * @return static
     */
    TRequest withoutAttribute(hstring name);
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
    int statusCode()
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
    mixin _ServerRequest!Request;
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
        418: "(Unused)", // [RFC9110, Section 15.5.19]
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
        510: "Not Extended (OBSOLETED)", // [RFC2774][status-change-http-experiments-to-historic]
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
            return "Server error responses";
        return "Whatever";
    }
}
