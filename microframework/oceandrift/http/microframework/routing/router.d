/++
    URL Router implementation
 +/
module oceandrift.http.microframework.routing.router;

import oceandrift.http.message;
import oceandrift.http.microframework.routing.middleware;
import oceandrift.http.microframework.routing.routetree;
import oceandrift.http.microframework.uri;
import oceandrift.http.server : RequestHandler, HTTPServer;
import std.conv : to;
import std.sumtype;

public import oceandrift.http.microframework.routing.routetree : RoutedRequestHandler, RouteMatchMeta;

@safe:

/++
    Creates a new router
    (and makes it available via an `out` parameter)

    Returns:
        The corresponding [oceandrift.http.server.server.RequestHandler|request handler]
 +/
RequestHandler makeRouterRequestHandler(out Router router)
{
    import oceandrift.http.server : listenHTTP;

    router = new Router();
    return &router.handleRequest;
}

///
alias MethodNotAllowedHandler = Response delegate(
    Request request,
    Response response,
    string[] allow,
) @safe;

///
alias RouteGroupSetupCallback = void delegate(Router) @safe;

/++
    HTTP Request Method (“verb”)

    See_Also:
        https://developer.mozilla.org/en-US/docs/Web/HTTP/Methods
 +/
enum HTTPMethod
{
    ///
    delete_,

    ///
    get,

    ///
    patch,

    ///
    post,

    ///
    put,
}

/++
    Returns the “verb” as string for the specified HTTP Request Method 
 +/
string toOptionsString(HTTPMethod method)
{
    final switch (method) with (HTTPMethod)
    {
    case delete_:
        return "DELETE";
    case get:
        return "GET";
    case patch:
        return "PATCH";
    case post:
        return "POST";
    case put:
        return "PUT";
    }
}

/++
    Collection of middleware (usually as part of a route)

    $(NOTE
        Not really relevant for regular framework users.

        See also:
            [oceandrift.http.microframework.routing.router.Route.add|Route.add]
    )
 +/
struct MiddlewareCollection
{
@safe:

    private
    {
        MiddlewareRequestHandler[] _middleware = [];
    }

    ///
    Response handleRequest(
        Request request,
        Response response,
        RequestHandler next,
        RoutedRequestHandler nextR,
        RouteMatchMeta meta,
    )
    {
        auto mwn = MiddlewareNext(_middleware, next, nextR, meta);
        return mwn(request, response);
    }

    ///
    void add(MiddlewareRequestHandler middleware)
    {
        _middleware ~= middleware;
    }
}

/++
    Request handling route
    with Middleware support
 +/
final class Route
{
@safe:

    /++
        Appends a middleware for the current route

        The middleware will be executed before the main request handler is called.
     +/
    Route add(MiddlewareRequestHandler middleware)
    {
        _middleware.add(middleware);
        return this;
    }

    ///
    Response handleRequest(Request request, Response response, RouteMatchMeta meta)
    {
        return _middleware.handleRequest(request, response, _target, _targetR, meta);
    }

private:

    this(RequestHandler target, RoutedRequestHandler targetR)
    in (((target !is null) && (targetR is null)) || ((target is null) && (targetR !is null)))
    {
        _target = target;
        _targetR = targetR;
        _middleware = MiddlewareCollection();
    }

    MiddlewareCollection _middleware;
    RequestHandler _target;
    RoutedRequestHandler _targetR;
}

private
{
    struct OptionsRequestMethodsArray
    {
        string[] methods;
        RoutedRequestHandler customHandler = null; // TODO: cannot be set currently

        private string _methodsString = null;

        string methodsString()
        {
            if (_methodsString is null)
            {
                _methodsString = methods[0];
                foreach (method; methods[1 .. $])
                    _methodsString ~= ", " ~ method;
            }

            return _methodsString;
        }
    }

    alias OptionsRequestMethodsImpl = SumType!(RoutedRequestHandler, OptionsRequestMethodsArray);

    // is a pointer to make it nullable
    alias OptionsRequestMethods = OptionsRequestMethodsImpl*;
}

private struct Routes
{
    RouteTreeNode!RoutedRequestHandler* delete_;
    RouteTreeNode!RoutedRequestHandler* get;
    RouteTreeNode!RoutedRequestHandler* patch;
    RouteTreeNode!RoutedRequestHandler* post;
    RouteTreeNode!RoutedRequestHandler* put;

    RouteTreeNode!OptionsRequestMethods* options;

    void setup()
    {
        delete_ = new RouteTreeNode!()();
        get = new RouteTreeNode!()();
        patch = new RouteTreeNode!()();
        post = new RouteTreeNode!()();
        put = new RouteTreeNode!()();
        options = new RouteTreeNode!OptionsRequestMethods();
    }
}

///
final class Router
{
@safe:

    private
    {
        Routes _routes;
        RequestHandler _404;
        MethodNotAllowedHandler _405;
        Response delegate(Request, Response, OptionsRequestMethods) _405alt;
    }

    /++
        See_Also:
            [oceandrift.http.microframework.routing.router.makeRouterRequestHandler|makeRouterRequestHandler]
     +/
    this()
    {
        _routes.setup();
    }

    /++
        Handles an incoming request

        $(NOTE
            There is usually no need to call this function manually.
            The frameworks startup routines (or [makeRouterRequestHandler]) have got you covered.

            The most likely case where you’ll want to call this function yourself is
            when you’re manually setting up an HTTP server.
        )
     +/
    Response handleRequest(Request request, Response response)
    {
        return this.handleRequest(request.uri.path, request, response);
    }

    ///
    Response handleRequest(hstring uri, Request request, Response response, RouteMatchMeta meta = RouteMatchMeta())
    {
        if (request.method.length < 3)
            return this.handle404(request, response);

        if (request.method == "GET")
        {
            return this.matchURL(_routes.get, uri, request, response, meta);
        }
        else if (request.method[0] == 'P')
        {
            if (request.method[1 .. $] == "OST")
                return this.matchURL(_routes.post, uri, request, response, meta);
            if (request.method[1 .. $] == "UT")
                return this.matchURL(_routes.put, uri, request, response, meta);
            if (request.method[1 .. $] == "ATCH")
                return this.matchURL(_routes.patch, uri, request, response, meta);
        }
        else if (request.method == "OPTIONS")
        {
            return this.handleOptionsRequest(uri, request, response);
        }
        else if (request.method == "HEAD")
        {
            return this.handleHeadRequest(uri, request, response, meta);
        }

        // unknown method
        return this.handleUnknown(uri, request, response);
    }

    /++
        Sets the Error 404 “Not Found” handler
     +/
    void notFoundHandler(RequestHandler h)
    in (h !is null)
    {
        _404 = h;
    }

    /++
        Sets the Error 405 “Method Not Allowed” handler
     +/
    void methodNotAllowedHandler(MethodNotAllowedHandler h)
    in (h !is null)
    {
        _405 = h;
    }

    ///
    Route delete_(string urlPattern, RequestHandler handler)
    {
        return addRoute!"delete_"(urlPattern, handler);
    }

    ///
    Route delete_(string urlPattern, RoutedRequestHandler handler)
    {
        return addRoute!"delete_"(urlPattern, handler);
    }

    ///
    Route get(string urlPattern, RequestHandler handler)
    {
        return addRoute!"get"(urlPattern, handler);
    }

    ///
    Route get(string urlPattern, RoutedRequestHandler handler)
    {
        return addRoute!"get"(urlPattern, handler);
    }

    ///
    Route patch(string urlPattern, RequestHandler handler)
    {
        return addRoute!"patch"(urlPattern, handler);
    }

    ///
    Route patch(string urlPattern, RoutedRequestHandler handler)
    {
        return addRoute!"patch"(urlPattern, handler);
    }

    ///
    Route post(string urlPattern, RequestHandler handler)
    {
        return addRoute!"post"(urlPattern, handler);
    }

    ///
    Route post(string urlPattern, RoutedRequestHandler handler)
    {
        return addRoute!"post"(urlPattern, handler);
    }

    ///
    Route put(string urlPattern, RequestHandler handler)
    {
        return addRoute!"put"(urlPattern, handler);
    }

    ///
    Route put(string urlPattern, RoutedRequestHandler handler)
    {
        return addRoute!"put"(urlPattern, handler);
    }

    ///
    Route group(string urlPattern, RouteGroupSetupCallback setup)
    in (urlPattern.length > 0)
    {
        if (urlPattern[$ - 1] != '*')
            urlPattern ~= '*';

        // create route
        // inherit not-found + method-not-allowed handlers from parent
        auto r = new Route(
            null,
            makeGroup((Router router) { this.setupChildRouter(router, setup); })
        );

        _routes.delete_.addRoute(urlPattern, &r.handleRequest);
        _routes.get.addRoute(urlPattern, &r.handleRequest);
        _routes.patch.addRoute(urlPattern, &r.handleRequest);
        _routes.post.addRoute(urlPattern, &r.handleRequest);
        _routes.put.addRoute(urlPattern, &r.handleRequest);
        registerRouteOptions(urlPattern, &r.handleRequest);
        return r;
    }

private:

    Route addRoute(string httpMethod)(string urlPattern, RoutedRequestHandler handlerR)
    {
        return this.addRoute!httpMethod(urlPattern, null, handlerR);
    }

    Route addRoute(string httpMethod)(string urlPattern, RequestHandler handler)
    {
        return this.addRoute!httpMethod(urlPattern, handler, null);
    }

    Route addRoute(string httpMethod)(string urlPattern, RequestHandler handler, RoutedRequestHandler handlerR)
    {
        pragma(inline, true);

        auto r = new Route(handler, handlerR);
        mixin("_routes." ~ httpMethod).addRoute(urlPattern, &r.handleRequest);

        // collect methods for OPTION requests (and error 405 messages)
        registerRouteOptions!httpMethod(urlPattern);

        return r;
    }

    // regular route
    void registerRouteOptions(string httpMethod)(string urlPattern)
    {
        {
            RouteMatchResult!OptionsRequestMethods r405 = _routes.options.match(urlPattern);
            enum HTTPMethod method = mixin(`HTTPMethod.` ~ httpMethod);

            // known route? i.e. have there been any allowed request methods registered yet?
            if (r405.requestHandler !is null)
            {
                // dfmt off
                (*r405.requestHandler).match!(
                    (ref OptionsRequestMethodsArray a) {
                        static if (method == HTTPMethod.get)
                            a.methods ~= "HEAD";
                        a.methods ~= method.toOptionsString;
                    },
                    (ref RoutedRequestHandler) {
                        assert(false);
                    }
                );
                // dfmt on
            }
            else
            {
                // new route

                static if (method == HTTPMethod.get)
                    string[] methods = [
                        "OPTIONS",
                        "HEAD",
                        method.toOptionsString,
                    ];
                else
                    string[] methods = [
                        "OPTIONS",
                        method.toOptionsString,
                    ];

                _routes.options.addRoute(
                    urlPattern,
                    new OptionsRequestMethodsImpl(OptionsRequestMethodsArray(methods))
                );
            }
        }
    }

    // group route
    void registerRouteOptions(string urlPattern, RoutedRequestHandler requestHandler)
    {
        RouteMatchResult!OptionsRequestMethods r405 = _routes.options.match(urlPattern);

        if (r405.requestHandler !is null)
            assert(false);

        _routes.options.addRoute(
            urlPattern,
            new OptionsRequestMethodsImpl(requestHandler)
        );
    }

    Response matchURL(
        RouteTreeNode!RoutedRequestHandler* root,
        hstring url,
        Request request,
        Response response,
        RouteMatchMeta meta,
    )
    {
        RouteMatchResult!RoutedRequestHandler r = root.match(url);

        // not found or method not allowed?
        if (r.requestHandler is null)
            return this.handleUnknown(url, request, response);

        // --> match

        // merge meta data
        meta = RouteMatchMeta.merge(meta, r.meta);

        return r.requestHandler(request, response, meta);
    }

    Response handle404(Request request, Response response)
    {
        // prepare default response
        response.statusCode = 404;

        // custom handler?
        if (_404 !is null)
            return _404(request, response);

        return response;
    }

    Response handle405(Request request, Response response, OptionsRequestMethods options)
    {
        return (*options).match!((OptionsRequestMethodsArray optionsA) {
            // prepare default response
            response.statusCode = 405;
            response.setHeader!"Allow" = optionsA.methodsString;

            // custom handler?
            if (_405 !is null)
                return _405(request, response, optionsA.methods);

            // alternative custom handler?
            if (_405alt !is null)
                return _405alt(request, response, options);

            return response;
        }, (RoutedRequestHandler) { assert(false); return Response(); });
    }

    Response handleHeadRequest(hstring uri, Request request, Response response, RouteMatchMeta meta)
    {
        response = this.matchURL(_routes.get, uri, request, response, meta);

        // has body?
        if (response.body !is null)
        {
            // determine length
            immutable long contentLength = response.body.knownLength;

            // length available?
            if (contentLength >= 0)
                response.setHeader!"Content-Length" = contentLength.to!string;

            // cut off body
            response.body = null;
        }

        return response;
    }

    // Handle HTTP OPTIONS request
    Response handleOptionsRequest(hstring uri, Request request, Response response)
    {
        // determine route
        RouteMatchResult!OptionsRequestMethods matching = _routes.options.match(uri);

        // not found?
        if (matching.requestHandler is null)
            return handle404(request, response);

        // dfmt off
        return (*matching.requestHandler).match!(
            (ref OptionsRequestMethodsArray a) {
                // prepare default response
                response.statusCode = 204;
                response.setHeader!"Allow" = a.methodsString;

                // call custom handler if applicable
                if (a.customHandler !is null)
                    return a.customHandler(request, response, matching.meta);

                return response;
            },
            (ref RoutedRequestHandler requestHandler) {
                return requestHandler(request, response, matching.meta);
            },
        );
        // dfmt on
    }

    Response handleUnknown(hstring uri, Request request, Response response)
    {
        RouteMatchResult!OptionsRequestMethods r405 = this._routes.options.match(uri);

        // error 405?
        if (r405.requestHandler !is null)
            return this.handle405(request, response, r405.requestHandler);

        // error 404
        return this.handle404(request, response);
    }

    // setup not-found/method-allowed handlers for child routers
    void setupChildRouter(Router router, RouteGroupSetupCallback callback)
    {
        // use parent router handlers by default
        // those can’t be assigned directly, because that wouldn’t reflect later updates of those handlers
        router.notFoundHandler = &this.handle404;
        router._405alt = &this.handle405;

        // call setup callback
        return callback(router);
    }
}

/++
    Route Group: child router helper
 +/
struct RouteGroup
{
    private
    {
        Router _router;
    }

    private this(Router router) pure nothrow @nogc
    {
        _router = router;
    }

    Response handleRequest(Request request, Response response, RouteMatchMeta meta)
    {
        debug assert(meta.placeholders.length > 0);

        RouteMatchMeta newMeta = meta;
        newMeta.placeholders.length -= 1;

        hstring uri;
        foreach (idx, placeholder; meta.placeholders)
        {
            // is deep wildcard?
            if (placeholder.key == "*")
            {
                uri = placeholder.value;
                newMeta.placeholders[idx .. $] = meta.placeholders[idx + 1 .. $];
                return _router.handleRequest(uri, request, response, newMeta);
            }
        }

        assert(false, "Invalid use of request group: no *-URI in meta");
    }
}

///
RoutedRequestHandler makeGroup(RouteGroupSetupCallback setup)
{
    auto router = new Router();
    setup(router);

    auto group = new RouteGroup(router);
    return &group.handleRequest;
}
