/++
    HTTP Message abstraction and representation

    This module’s design was inspired by “PSR-7: HTTP message interfaces”
    created by the PHP Framework Interoperability Group.

    See_Also:
    $(LIST
        * https://www.php-fig.org/psr/psr-7/
    )
+/
module oceandrift.http.message.messages;

import oceandrift.http.message.htype;
import oceandrift.http.message.lowercasetoken;
import oceandrift.http.message.multibuffer;
import std.traits : ReturnType;

@safe pure:

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

///
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
