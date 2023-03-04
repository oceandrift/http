/++
    HTTP Cookies

    Request Cookies can be accessed via [getCookie].

    To set response Cookies, there are two options:
    $(LIST
        * [cookieMiddleware] + [setCookie] – handles duplicates
        * [setCookieDirectly]
    )

    ---
    router.get("/my-route",  delegate(Request request, Response response) {
        // get Cookie “MyCookie” from request
        hstring cookieValue = request.getCookie("MyCookie");

        // was the Cookie actually set?
        bool cookieSet = (cookieValue is null);

        // set a response Cookie
        response.setCookie(Cookie("MyCookie", "foobar"));

        return response;
    }).add(cookiesMiddleware); // <-- add cookie middleware
    ---

    ---
    // apply Cookie header directly (no middleware needed)
    response.setCookieDirectly("MyCookie", "foobar");
    ---
 +/
module oceandrift.http.microframework.cookies;

import oceandrift.http.message : hstring, Response;
import oceandrift.http.microframework.middleware;
import std.typecons : Nullable;

@safe:

private static immutable tagName = "oceandrift.http.microframework.cookies";
private alias Cookies = Cookie[hstring];

/++
    Retrieves a cookie from a request

    ---
    hstring sessionID = request.getCookie("SESSID");

    if (sessionID is null) {
       // cookie not set
    }
    ---

    Returns:
        $(LIST
            * the cookie’s value
            * `null` = not found
        )
 +/
hstring getCookie(Request request, hstring name)
{
    import oceandrift.http.microframework.parsing.hparser;

    foreach (cookieData; request.getHeader!"Cookie")
    {
        foreach (KeyValuePair cookie; parseHeaderValueParams(cookieData))
            if (cookie.key == name)
                return cookie.value;
    }

    return null;
}

unittest
{
    Request request;

    request.setHeader!"Cookie"("cookie-name=cookie-value");
    assert(request.getCookie("cookie-name") == "cookie-value");
    assert(request.getCookie("not-found") is null);

    request.setHeader!"Cookie"("PHPSESSID=298zf09hf012fh2; csrftoken=u32t4o3tb3gg43; _gat=1");
    assert(request.getCookie("_gat") == "1");
    assert(request.getCookie("PHPSESSID") == "298zf09hf012fh2");
    assert(request.getCookie("csrftoken") == "u32t4o3tb3gg43");
}

/++
    Cookies Middleware

    This middleware applies scheduled cookies to the response before the request is sent.

    See_Also:
        [setCookie]
 +/
enum MiddlewareRequestHandler cookiesMiddleware = delegate(
        Request request,
        Response response,
        MiddlewareNext next,
        RouteMatchMeta,
    ) @safe {
    () @trusted { response.tags[tagName] = (Cookie[hstring]).init; }();

    // handle request
    response = next(request, response);

    // apply cookies (set headers)
    auto cookiesV = tagName in response.tags;
    if (cookiesV is null)
        return response;

    auto cookies = () @trusted { return cookiesV.peek!Cookies; }();
    if (cookies is null)
        return response;

    foreach (cookie; *cookies)
        response.setCookieDirectly(cookie);

    // remove cookies from thread-local storage
    response.tags.remove(tagName);

    return response;
};

/++
    Retrieves a cookie that has been set (scheduled) for a response

    $(PITFALL
        This function doesn’t check for already applied `Set-Cookie` headers.
    )
 +/
Cookie* getCookie(Response response, hstring name)
{
    auto tagData = tagName in response.tags;

    if (tagData is null)
        return null;

    auto cookies = () @trusted { return tagData.peek!Cookies; }();
    if (cookies is null)
        assert(false, "Invalid data in cookie tag");

    return name in (*cookies);
}

/++
    Sets a response Cookie

    Relies on [cookiesMiddleware] to actually apply it.
    This function only schedules the cookie to be applied later.

    See_Also:
        [setCookieDirectly] to apply a cookie directly to a response
 +/
void setCookie(ref Response response, Cookie cookie) @trusted
in (cookie.name.length > 0)
{
    // load cookie data from response tags
    auto tagData = tagName in response.tags;

    // no cookie data yet?
    if (tagData is null)
        () @trusted { response.tags[tagName] = (Cookie[hstring]).init; }();
    else
    {
        // cookie data valid (correct type)?
        auto cookies = () @trusted { return tagData.peek!Cookies; }();
        if (cookies is null)
            assert(false, "Invalid data in cookie tag");

        // if the assert above fails,
        // this most likely indicates that a different library is causing interferences
        // by (re)using this module’s tag name
    }

    response.tags[tagName][cookie.name] = cookie;
}

unittest
{
    Response response;
    response.setCookie(Cookie("abc", "xyz"));
    response.setCookie(Cookie("foo", "bar"));

    assert(response.getCookie("foobar") is null);

    assert(response.getCookie("abc") !is null);
    assert(response.getCookie("abc").value == "xyz");

    assert(response.getCookie("foo") !is null);
    assert(response.getCookie("foo").value == "bar");
}

/++
    HTTP Cookie

    See_Also:
        https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Set-Cookie
 +/
struct Cookie
{
    ///
    hstring name;

    ///
    hstring value;

    ///
    Nullable!long maxAge;

    ///
    SameSite sameSite = SameSite.lax;

    ///
    hstring domain = null;

    ///
    hstring path = null;

    ///
    bool secure = false;

    ///
    bool httpOnly = true;

    ///
    enum SameSite
    {
        ///
        lax,

        ///
        strict,

        ///
        none,
    }
}

/++
    Appends a Set-Cookie header to a response directly

    $(WARNING
        Does not check for duplicates.
    )

    See_Also:
        [setCookie]
 +/
void setCookieDirectly(ref Response response, Cookie cookie) pure
{
    import std.array : appender;
    import std.conv : to;

    // build header value using an appender
    auto headerValue = appender!hstring();

    headerValue ~= cookie.name;
    headerValue ~= '=';
    headerValue ~= cookie.value;

    if (!cookie.maxAge.isNull)
    {
        headerValue ~= "; Max-Age=";
        headerValue ~= cookie.maxAge.get.to!string;
    }

    final switch (cookie.sameSite) with (Cookie.SameSite)
    {
    case lax:
        headerValue ~= "; SameSite=Lax";
        break;
    case strict:
        headerValue ~= "; SameSite=Strict";
        break;
    case none:
        headerValue ~= "; SameSite=None";
        break;
    }

    if (cookie.domain !is null)
    {
        headerValue ~= "; Domain=";
        headerValue ~= cookie.domain;
    }

    if (cookie.path !is null)
    {
        headerValue ~= "; Path=";
        headerValue ~= cookie.path;
    }

    if (cookie.secure)
        headerValue ~= "; Secure";

    if (cookie.httpOnly)
        headerValue ~= "; HttpOnly";

    // add header
    response.addHeader!"Set-Cookie"(headerValue.data);
}

unittest
{
    import std.typecons : Nullable;

    Response response;

    auto cookie = Cookie("foo", "bar");
    cookie.sameSite = Cookie.SameSite.strict;
    response.setCookieDirectly(cookie);

    auto cookieHeader = response.getHeader!"Set-Cookie";
    assert(cookieHeader.length == 1);
    assert(cookieHeader[0] == "foo=bar; SameSite=Strict; HttpOnly");
}

unittest
{
    Response response;

    auto cookie = Cookie("foo", "bar");
    cookie.maxAge = 3600;
    cookie.secure = true;
    cookie.httpOnly = false;
    response.setCookieDirectly(cookie);

    auto cookieHeader = response.getHeader!"Set-Cookie";
    assert(cookieHeader.length == 1);
    assert(cookieHeader[0] == "foo=bar; Max-Age=3600; SameSite=Lax; Secure");
}
