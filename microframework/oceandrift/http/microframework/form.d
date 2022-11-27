/++
    Form data and Query Params handling
 +/
module oceandrift.http.microframework.form;

import std.string : indexOf;
import oceandrift.http.message : Request;
import oceandrift.http.microframework.uri;

public import oceandrift.http.message : hstring;
public import oceandrift.http.microframework.kvp;

@safe pure nothrow:

/++
    Parses a query component

    (e.g. “q=search+term”)

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
}

/++
    Parses a query string

    (e.g. “q=search+term&category=things1”)

    See_Also:
        [queryParams] for parsing query strings from whole [Request]s
 +/
KeyValuePair[] parseQueryString(const hstring queryString)
{
    KeyValuePair[] output = [];
    hstring query = queryString;

    while (true)
    {
        ptrdiff_t next = query.indexOf('&');

        if (next < 0) // last element?
        {
            if (query.length == 0)
                break;

            output ~= parseQueryComponent(query);
            break;
        }

        output ~= parseQueryComponent(query[0 .. next]);

        query = query[(next + 1) .. $]; //
    }

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
