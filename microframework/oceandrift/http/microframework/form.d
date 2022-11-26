/++
    Form data and Query Params handling
 +/
module oceandrift.http.microframework.form;

import std.string : indexOf;
import oceandrift.http.message : Request;
import oceandrift.http.microframework.uri;

public import oceandrift.http.message : hstring;

@safe pure nothrow:

/// Key+Value Pair
struct KeyValuePair
{
    /// Key
    hstring key;

    /// Associated value
    hstring value;
}

/++
    Determines whether a [KeyValuePair] with the specified key exists in the passed array

    Returns:
        true = if a matching KeyValuePair was found
 +/
bool contains(KeyValuePair[] array, hstring key)
{
    foreach (kvp; array)
        if (kvp.key == key)
            return true;

    return false;
}

/++
    Determines whether a [KeyValuePair] with the specified key exists in the passed array

    Also makes it available through an out parameter.

    Params:
        result = value of the KeyValuePair – only valid when this function returned true

    Returns:
        true = if a matching KeyValuePair was found
 +/
bool tryGet(KeyValuePair[] array, hstring key, out hstring result)
{
    foreach (kvp; array)
    {
        if (kvp.key == key)
        {
            result = kvp.value;
            return true;
        }
    }

    return false;
}

/++
    Returns the value of the [KeyValuePair] with the specified key in the passed array
 +/
hstring get(KeyValuePair[] array, hstring key)
{
    foreach (kvp; array)
        if (kvp.key == key)
            return kvp.value;

    assert(false, "Key does not exist in input array");
}

/++
    Parses a query component (e.g. “q=search+term”)

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
    Parses a query component (e.g. “q=search+term”)

    See_Also:
        [queryParams] for parsing query strings from whole [Request]s
 +/
KeyValuePair[] parseQueryString(const hstring url)
{
    hstring query = url.query;

    KeyValuePair[] output = [];

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
    {
        const q = parseQueryString("https://forum.dlang.org/search?q=search+term&scope=forum");
        assert(q[0] == KeyValuePair("q", "search+term"));
        assert(q[1] == KeyValuePair("scope", "forum"));
    }

    {
        const q = parseQueryString("/search?q=search+term&scope=forum");
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
    return parseQueryString(request.uri);
}
