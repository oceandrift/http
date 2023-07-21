/++
    HTTP Authentication implementation

    Standards: $(LIST
        * RFC 7617 – “The 'Basic' HTTP Authentication Scheme”
    )
 +/
module oceandrift.http.microframework.httpauth;

import oceandrift.http.message : hstring, Request, Response;
import oceandrift.http.microframework.routing.middleware;
import std.algorithm : canFind;
import std.string : indexOf, startsWith;

///
alias CredentialsCheckFunction = bool delegate(Credentials) @safe;

/++
    Basic Auth Middleware

    Handles basic auth for incoming requests.
    Stops requests that have no or bad credentials from further processing.
 +/
MiddlewareRequestHandler basicAuthMiddleware(string realm)(CredentialsCheckFunction checkCredentials) @safe
{
    return delegate(Request request, Response response, MiddlewareNext next, RouteMatchMeta meta) @safe {
        BasicAuthCredentials baCred = request.basicAuthCredentials;

        if (baCred.isUnauthorized)
            return response.withBasicAuth!realm();

        if (baCred.isBadRequest)
            return response.withStatus(400);

        assert(baCred.isOK);

        if (!checkCredentials(baCred.credentials))
            return response.withBasicAuth!realm();

        function(ref Request request, hstring username) @trusted {
            request.tags["auth-user"] = username;
        }(request, baCred.credentials.username);

        return next(request, response);
    };
}

unittest
{
    auto mw = basicAuthMiddleware!"Dings"(delegate(Credentials cred) @safe {
        return ((cred.username == "Oachkatzl") && (cred.password == "schwoaf"));
    });

    // auth success
    auto r = Request();
    r.setHeader!"Authorization"("Basic T2FjaGthdHpsOnNjaHdvYWY=");
    bool hasBeenCalled = false;
    mw(r, Response(), MiddlewareNext(null, delegate(Request request, Response response) @trusted {
            hasBeenCalled = true;
            assert(request.tags["auth-user"].get!hstring == "Oachkatzl");
            return response;
        }, null, RouteMatchMeta()), RouteMatchMeta());
    assert(hasBeenCalled);

    // auth fail
    r = Request();
    r.setHeader!"Authorization"("Basic U2Nod29hY2hrYXR6bDpvYWY=");
    hasBeenCalled = false;
    mw(r, Response(), MiddlewareNext(null, delegate(Request request, Response response) @trusted {
            hasBeenCalled = true;
            return response;
        }, null, RouteMatchMeta()), RouteMatchMeta());
    assert(!hasBeenCalled);
}

@safe pure nothrow:

///
struct Credentials
{
    ///
    hstring username;

    ///
    hstring password;
}

/++
    Adds a `WWW-Authenticate: Basic […]` header to a response
    and sets status to 401
 +/
Response withBasicAuth(string realm)(ref Response response)
{
    static assert(
        !realm.canFind('"'),
        "`realm` must not contain `\"`"
    );

    static immutable hValue = `Basic realm="` ~ realm ~ `", charset="UTF-8"`;
    return response
        .withStatus(401)
        .withHeader!"WWW-Authenticate"(hValue);
}

unittest
{
    auto r = Response();
    r.statusCode = 200;
    r.withBasicAuth!"Oachkatzlschwoaf"();
    assert(r.statusCode == 401);
    assert(r.hasHeader!"WWW-Authenticate");
    assert(r.getHeader!"WWW-Authenticate" == [
        `Basic realm="Oachkatzlschwoaf", charset="UTF-8"`
    ]);
}

///
struct BasicAuthCredentials
{
@safe pure nothrow @nogc:

    ///
    enum Status
    {
        unknown,
        missingHeader,
        otherScheme,
        badHeader,
        ok,
    }

    ///
    Status status;

    ///
    Credentials credentials;

    ///
    bool isOK()
    {
        return (status == Status.ok);
    }

    ///
    bool isUnauthorized()
    {
        return (
            (status == Status.missingHeader)
                || (status == Status.otherScheme)
        );
    }

    ///
    bool isBadRequest()
    {
        return (status == Status.badHeader);
    }
}

/++
    Retrieves the HTTP Basic Auth credentials from a request

    Standards:
        RFC 7617
 +/
BasicAuthCredentials basicAuthCredentials(ref Request request)
{
    import std.base64;

    const hstring[] hValues = request.getHeader!"Authorization"();

    hstring credBase64 = null;

    // no header
    if (hValues.length == 0)
    {
        return BasicAuthCredentials(BasicAuthCredentials.Status.missingHeader);
    }
    // one header
    else if (hValues.length == 1)
    {
        const hValue = hValues[0];

        if (!hValue.startsWith("Basic"))
            return BasicAuthCredentials(BasicAuthCredentials.Status.otherScheme);

        // 10 --> "Basic Og==" --> "Basic <none>:<none>"
        // Length check is needed anyway, so why not do a more advanced one?
        if ((hValue.length < 10) || (hValue[5] != ' '))
            return BasicAuthCredentials(BasicAuthCredentials.Status.badHeader);

        credBase64 = hValue[6 .. $];
    }
    // split header
    else if (hValues.length == 2)
    {
        if (hValues[0] != "Basic")
            return BasicAuthCredentials(BasicAuthCredentials.Status.otherScheme);

        credBase64 = hValues[1];
    }
    // defective header (there can only be a single space)
    else
    {
        const hValue = hValues[0];
        if ((hValue.length == 5) && (hValue == "Basic"))
            return BasicAuthCredentials(BasicAuthCredentials.Status.badHeader);

        if (hValue.startsWith("Basic "))
            return BasicAuthCredentials(BasicAuthCredentials.Status.badHeader);

        return BasicAuthCredentials(BasicAuthCredentials.Status.otherScheme);
    }

    hstring cred;
    try
        cred = cast(hstring) Base64.decode(credBase64);
    catch (Exception)
        return BasicAuthCredentials(BasicAuthCredentials.Status.badHeader);

    immutable idxSep = cred.indexOf(':');
    if (idxSep < 0)
        return BasicAuthCredentials(BasicAuthCredentials.Status.badHeader);

    return BasicAuthCredentials(
        BasicAuthCredentials.status.ok,
        Credentials(cred[0 .. idxSep], cred[(idxSep + 1) .. $]),
    );
}

unittest
{
    auto r = Request();
    r.setHeader!"Authorization"("Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==");

    auto bac = r.basicAuthCredentials;
    assert(bac.status == BasicAuthCredentials.Status.ok);
    assert(bac.isOK);
    assert(!bac.isBadRequest);
    assert(!bac.isUnauthorized);
    assert(bac.credentials == Credentials("Aladdin", "open sesame"));
}

unittest
{
    auto r = Request();
    r.addHeader!"Authorization"("Basic");
    r.addHeader!"Authorization"("QWxhZGRpbjpvcGVuIHNlc2FtZQ==");

    auto bac = r.basicAuthCredentials;
    assert(bac.isOK);
    assert(bac.credentials == Credentials("Aladdin", "open sesame"));
}

unittest
{
    auto r = Request();
    r.setHeader!"Authorization"("Basic");
    assert(!r.basicAuthCredentials.isOK);
    assert(r.basicAuthCredentials.isBadRequest);
    assert(r.basicAuthCredentials.status == BasicAuthCredentials.Status.badHeader);
}

unittest
{
    auto r = Request();
    r.setHeader!"Authorization"(`Digest username="Oachkatzlschwoaf",realm="Gulasch"`);
    assert(r.basicAuthCredentials.isUnauthorized);
    assert(r.basicAuthCredentials.status == BasicAuthCredentials.status.otherScheme);
}

unittest
{
    auto r = Request();
    r.setHeader!"Authorization"("Basic T2FjaGthdHpsc2Nod29hZjpzdXBlcjpnZWhlaW0=");
    assert(r.basicAuthCredentials.isOK);
    assert(r.basicAuthCredentials.credentials == Credentials("Oachkatzlschwoaf", "super:geheim"));
}

unittest
{
    auto r = Request();
    r.setHeader!"Authorization"("Basic T2FjaGthdHpsc2Nod29hZjo=");
    assert(r.basicAuthCredentials.isOK);
    assert(r.basicAuthCredentials.credentials == Credentials("Oachkatzlschwoaf", ""));
}

unittest
{
    auto r = Request();
    r.setHeader!"Authorization"("Basic Ok9hY2hrYXR6bHNjaHdvYWY=");
    assert(r.basicAuthCredentials.isOK);
    assert(r.basicAuthCredentials.credentials == Credentials("", "Oachkatzlschwoaf"));
}

unittest
{
    auto r = Request();
    assert(!r.basicAuthCredentials.isOK);
    assert(!r.basicAuthCredentials.isBadRequest);
    assert(r.basicAuthCredentials.isUnauthorized);
    assert(r.basicAuthCredentials.status == BasicAuthCredentials.Status.missingHeader);
}

unittest
{
    auto r = Request();
    r.setHeader!"Authorization"("Basic Og==");
    assert(r.basicAuthCredentials.isOK);
    assert(r.basicAuthCredentials.credentials == Credentials("", ""));
}

unittest
{
    auto r = Request();
    r.addHeader!"Authorization"("Basic");
    r.addHeader!"Authorization"("QWxhZGRpbjpvc");
    r.addHeader!"Authorization"("GVuIHNlc2FtZQ==");

    assert(r.basicAuthCredentials.isBadRequest);
}

unittest
{
    auto r = Request();
    r.addHeader!"Authorization"("Digest");
    r.addHeader!"Authorization"(`realm="Gulasch"`);
    r.addHeader!"Authorization"(`username="Oachkatzl"`);

    assert(r.basicAuthCredentials.isUnauthorized);
}
