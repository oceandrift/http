/++
    Form data and Query Params handling
 +/
module oceandrift.http.microframework.form;

import std.string : indexOf;
import oceandrift.http.message : MultiBuffer, Request;
import oceandrift.http.microframework.uri;

public import oceandrift.http.message : hstring;
public import oceandrift.http.microframework.kvp;
import oceandrift.http.microframework.multipart;

@safe pure nothrow:

/++
    Parses a query component

    (e.g. “q=search+term”)

    Returns:
        [KeyValuePair] – key will be empty if the input was bogus

    See_Also:
        $(LIST
            - [parseQueryString] for parsing query strings (with multiple components)
            - [queryParams] for parsing query strings from whole [Request]s
        )
 +/
KeyValuePair parseQueryComponent(hstring rawQueryComponent) @nogc
{
    immutable ptrdiff_t eq = rawQueryComponent.indexOf('=');

    // dfmt off
    return (eq < 0)
        ? KeyValuePair(rawQueryComponent, null)
        : KeyValuePair(rawQueryComponent[0 .. eq], rawQueryComponent[(eq + 1) .. $])
    ;
    // dfmt on
}

///
unittest
{
    assert(parseQueryComponent("q=term") == KeyValuePair("q", "term"));
    assert(parseQueryComponent("foo=bar") == KeyValuePair("foo", "bar"));

    // Key only, no value
    assert(parseQueryComponent("foo") == KeyValuePair("foo", null));
    assert(parseQueryComponent("foo") == KeyValuePair("foo", ""));
    assert(parseQueryComponent("foo=") == KeyValuePair("foo", null));

    // bogus
    assert(parseQueryComponent("=") == KeyValuePair(null, null));
    assert(parseQueryComponent("") == KeyValuePair(null, null));
    assert(parseQueryComponent("==") == KeyValuePair(null, "=")); // non-sensical though
}

/++
    Parses a query string

    (e.g. “q=search+term&category=things1”)

    See_Also:
        [queryParams] for parsing query strings from whole [Request]s
 +/
KeyValuePair[] parseQueryString(const hstring queryString)
{
    // TODO: Range version

    KeyValuePair[] output = [];
    hstring query = queryString;

    do
    {
        // locate separator
        immutable ptrdiff_t next = query.indexOf('&');

        // last element?
        immutable endOfComponent = (next < 0) ? query.length : next;

        // parse the query component
        KeyValuePair kvp = parseQueryComponent(query[0 .. endOfComponent]);

        // non-bogus?
        if (kvp.key.length > 0)
            output ~= kvp;

        // last element? → break “endless” loop
        if (next < 0)
            break;

        // advance buffer view
        query = query[(endOfComponent + 1) .. $];
    }
    while (true);

    return output;
}

///
unittest
{
    assert(parseQueryString("q=search+term&category=things1") == [
            KeyValuePair("q", "search+term"),
            KeyValuePair("category", "things1"),
        ]
    );

    assert(parseQueryString("q=search+term") == [
            KeyValuePair("q", "search+term"),
        ]
    );

    assert(parseQueryString("he%20y=there&s%20e%20e=you&nice%20=to%20meet%20you") == [
            KeyValuePair("he%20y", "there"),
            KeyValuePair("s%20e%20e", "you"),
            KeyValuePair("nice%20", "to%20meet%20you"),
        ]
    );

    assert(parseQueryString("this-is=bogus&") == [
            KeyValuePair("this-is", "bogus"),
        ]
    );
    assert(parseQueryString("this-is=bogus&&") == [
            KeyValuePair("this-is", "bogus"),
        ]
    );
    assert(parseQueryString("&&this-is=bogus") == [
            KeyValuePair("this-is", "bogus"),
        ]
    );
    assert(parseQueryString("&&this-is=bogus&&") == [
            KeyValuePair("this-is", "bogus"),
        ]
    );
    assert(parseQueryString("&&this-is=bogus&&&as==can-be&&&&x&&") == [
            KeyValuePair("this-is", "bogus"),
            KeyValuePair("as", "=can-be"),
            KeyValuePair("x", null),
        ]
    );
}

/++
    Parses a query string from a URL

    (e.g. “http://example.com?q=search+term”)

    See_Also:
        [queryParams] for parsing query strings from whole [Request]s
 +/
KeyValuePair[] parseQueryStringFromURL(const hstring url)
{
    return parseQueryString(url.query);
}

///
unittest
{
    {
        const q = parseQueryStringFromURL(
            "https://forum.dlang.org/search?q=search+term&scope=forum");
        assert(q[0] == KeyValuePair("q", "search+term"));
        assert(q[1] == KeyValuePair("scope", "forum"));
    }

    {
        const q = parseQueryStringFromURL("/search?q=search+term&scope=forum");
        assert(q[0] == KeyValuePair("q", "search+term"));
        assert(q[1] == KeyValuePair("scope", "forum"));
    }
}

/++
    Returns the query parameters (aka “GET” parameters) of a Request

    See_Also:
    $(LIST
        - [contains] – to determine whether the query params array contains a certain query param
        - [get] – to (optimistically) retrieve a query param from the params array by name
        - [tryGet] – to retrieve a query param from the params array by name
    )
 +/
KeyValuePair[] queryParams(const Request request)
{
    return parseQueryStringFromURL(request.uri);
}

private
{
    enum contentTypeMultipart = "multipart/form-data;";
    enum contentTypeURLEncoded = "application/x-www-form-urlencoded";
}

/++
    Standards:
        https://www.rfc-editor.org/rfc/rfc7578
+/
KeyValuePair[] formData(Request request)
{
    import std.string : startsWith;

    hstring[] contentType = request.getHeader!"Content-Type";
    if (contentType.length == 0)
        return null;

    // form urlencoded?
    if (contentType[0] == contentTypeURLEncoded)
        return parseFormDataURLEncoded(request.body_.toString());

    // multipart form?
    if (contentType[0].startsWith(contentTypeMultipart))
        return parseFormDataMultipart(contentType[0], request.body_);

    return null;
}
/++
    Standards:
        https://www.rfc-editor.org/rfc/rfc7578
+/
bool tryGetFormData(Request request, out KeyValuePair[] formData)
{
    hstring[] contentType = request.getHeader!"Content-Type";
    if (contentType.length == 0)
        return false;

    // form urlencoded?
    if (contentType[0] == contentTypeURLEncoded)
    {
        formData = parseFormDataURLEncoded(request.body_.toString());
        return true;
    }

    if (contentType[0][0 .. contentTypeMultipart.length] == contentTypeMultipart)
    {
        formData = parseFormDataMultipart(contentType[0], request.body_);
        return true;
    }

    return false;
}

KeyValuePair[] parseFormDataURLEncoded(hstring bodyData)
{
    KeyValuePair[] output = parseQueryString(bodyData);

    foreach (ref item; output)
        item = KeyValuePair(urlDecode(item.key).toHString, urlDecode(item.value).toHString);

    return output;
}

KeyValuePair[] parseFormDataMultipart(const hstring contentType, ref MultiBuffer body)
{

    hstring boundary = determineMultipartBoundary(contentType);
    auto multipart = parseMultipart(body, boundary);

    KeyValuePair[] output = [];
    foreach (MultipartFile mpf; multipart)
        if (mpf.contentDisposition.main == "form-data")
            output ~= KeyValuePair(mpf.formDataName, cast(hstring) mpf.data);

    return output;
}

/++
    Name

    $(PITFALL
        Might not be unique.
    )

    Standards:
        See RFC 7578, 4.3. “Multiple Files for One Form Field”
 +/
private hstring formDataName(MultipartFile file) @nogc
{
    foreach (ref param; file.contentDisposition.params)
        if (param.key == "name")
            return param.value;
    return null;
}
