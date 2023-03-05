/++
    URL Router implementation
 +/
module oceandrift.http.microframework.routing.router;

import std.conv : to;
import std.sumtype;
import oceandrift.http.message;
import oceandrift.http.microframework.routing.middleware;
import oceandrift.http.microframework.routing.routetree;
import oceandrift.http.microframework.uri;
import oceandrift.http.server : RequestHandler, HTTPServer;

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

alias MethodNotAllowedHandler = Response delegate(
    Request request,
    Response response,
    string[] allow,
) @safe;

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

private struct OptionsRequestMethodsImpl
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

private alias OptionsRequestMethods = OptionsRequestMethodsImpl*;

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
        if (request.method.length < 3)
            return this.handle404(request, response);

        if (request.method == "GET")
        {
            return this.matchURL(_routes.get, request.uri, request, response);
        }
        else if (request.method[0] == 'P')
        {
            if (request.method[1 .. $] == "OST")
                return this.matchURL(_routes.post, request.uri, request, response);
            if (request.method[1 .. $] == "UT")
                return this.matchURL(_routes.put, request.uri, request, response);
            if (request.method[1 .. $] == "ATCH")
                return this.matchURL(_routes.patch, request.uri, request, response);
        }
        else if (request.method == "OPTIONS")
        {
            return handleOptionsRequest(request, response);
        }
        else if (request.method == "HEAD")
        {
            return this.handleHeadRequest(request, response);
        }

        // unknown method
        return this.handleUnknown(request, response);
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
        mixin("_routes." ~ httpMethod ~ ".addRoute(urlPattern, &r.handleRequest);");

        // collect methods for OPTION requests (and error 405 messages)
        {
            RouteMatchResult!OptionsRequestMethods r405 = _routes.options.match(urlPattern);
            enum HTTPMethod method = mixin(`HTTPMethod.` ~ httpMethod);

            // known route? i.e. have there been any allowed request methods registered yet?
            if (r405.requestHandler !is null)
            {
                static if (method == HTTPMethod.get)
                    r405.requestHandler.methods ~= "HEAD";

                r405.requestHandler.methods ~= method.toOptionsString;
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
                    new OptionsRequestMethodsImpl(methods)
                );
            }
        }

        return r;
    }

    Response matchURL(RouteTreeNode!RoutedRequestHandler* root, hstring url, Request request, Response response)
    {
        url = url.path;

        RouteMatchResult!RoutedRequestHandler r = root.match(url);

        // not found or method not allowed?
        if (r.requestHandler is null)
            return this.handleUnknown(request, response);

        // match
        return r.requestHandler(request, response, r.meta);
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
        // prepare default response
        response.statusCode = 405;
        response.setHeader!"Allow" = options.methodsString;

        // custom handler?
        if (_405 !is null)
            return _405(request, response, options.methods);

        return response;
    }

    Response handleHeadRequest(Request request, Response response)
    {
        response = this.matchURL(_routes.get, request.uri, request, response);

        // has body?
        if (response.body_ !is null)
        {
            // determine length
            immutable long contentLength = response.body_.knownLength;

            // length available?
            if (contentLength >= 0)
                response.setHeader!"Content-Length" = contentLength.to!string;

            // cut off body
            response.body = null;
        }

        return response;
    }

    Response handleOptionsRequest(Request request, Response response)
    {
        // determine route
        RouteMatchResult!OptionsRequestMethods match = _routes.options.match(request.uri.path);

        // not found?
        if (match.requestHandler is null)
            return handle404(request, response);

        // prepare default response
        response.statusCode = 204;
        response.setHeader!"Allow" = match.requestHandler.methodsString;

        // call custom handler if applicable
        if (match.requestHandler.customHandler !is null)
            response = match.requestHandler.customHandler(request, response, match.meta);

        return response;
    }

    Response handleUnknown(Request request, Response response)
    {
        RouteMatchResult!OptionsRequestMethods r405 = this._routes.options.match(request.uri.path);

        // error 405?
        if (r405.requestHandler !is null)
            return this.handle405(request, response, r405.requestHandler);

        // error 404
        return this.handle404(request, response);
    }
}
