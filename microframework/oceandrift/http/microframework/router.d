module oceandrift.http.microframework.router;

import std.sumtype;
import oceandrift.http.message;
import oceandrift.http.microframework.routetree;
import oceandrift.http.microframework.uri;
import oceandrift.http.server : RequestHandler, Server;

public import oceandrift.http.microframework.routetree : RoutedRequestHandler, RouteMatchMeta;

@safe:

Server bootWithRouter(out Router router)
{
    import oceandrift.http.server : boot;

    router = new Router();
    return boot(&router.handleRequest);
}

alias MiddlewareRequestHandler = Response delegate(
    Request request,
    Response response,
    RequestHandler next,
) @safe;

alias MethodNotAllowedHandler = Response delegate(
    Request request,
    Response response,
    HTTPMethod[] allow,
) @safe;

enum HTTPMethod
{
    delete_,
    get,
    patch,
    post,
    put,
}

struct MiddlewareCollection
{
    MiddlewareRequestHandler[] middleware = [];
}

final class Route
{
@safe:

    Route add()
    {
        return this;
    }

    Response handleRequest(Request request, Response response, RouteMatchMeta meta)
    {
        return (_target !is null) ? _target(request, response) : _targetR(request, response, meta);
    }

private:

    this(RequestHandler target, RoutedRequestHandler targetR)
    in (((target !is null) && (targetR is null)) || ((target is null) && (targetR !is null)))
    {
        _target = target;
        _middleware = new MiddlewareCollection();
    }

    MiddlewareCollection* _middleware;
    RequestHandler _target;
    RoutedRequestHandler _targetR;
}

private struct Routes
{
    RouteTreeNode* delete_;
    RouteTreeNode* get;
    RouteTreeNode* patch;
    RouteTreeNode* post;
    RouteTreeNode* put;

    RouteTreeNode* options;

    void setup()
    {
        delete_ = new RouteTreeNode();
        get = new RouteTreeNode();
        patch = new RouteTreeNode();
        post = new RouteTreeNode();
        put = new RouteTreeNode();
        options = new RouteTreeNode();
    }
}

final class Router
{
@safe:

    private
    {
        Routes _routes;
        RequestHandler _404;
        MethodNotAllowedHandler _405;
    }

    this()
    {
        _routes.setup();
    }

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
        }
        else if (request.method == "HEAD")
        {
        }

        return this.handle404(request, response);
    }

    void notFoundHandler(RequestHandler h)
    in (h !is null)
    {
        _404 = h;
    }

    void methodNotAllowedHandler(MethodNotAllowedHandler h)
    in (h !is null)
    {
        _405 = h;
    }

    Route delete_(string urlPattern, RequestHandler handler)
    {
        return addRoute!"delete_"(urlPattern, handler);
    }

    Route delete_(string urlPattern, RoutedRequestHandler handler)
    {
        return addRoute!"delete_"(urlPattern, handler);
    }

    Route get(string urlPattern, RequestHandler handler)
    {
        return addRoute!"get"(urlPattern, handler);
    }

    Route get(string urlPattern, RoutedRequestHandler handler)
    {
        return addRoute!"get"(urlPattern, handler);
    }

    Route patch(string urlPattern, RequestHandler handler)
    {
        return addRoute!"patch"(urlPattern, handler);
    }

    Route patch(string urlPattern, RoutedRequestHandler handler)
    {
        return addRoute!"patch"(urlPattern, handler);
    }

    Route post(string urlPattern, RequestHandler handler)
    {
        return addRoute!"post"(urlPattern, handler);
    }

    Route post(string urlPattern, RoutedRequestHandler handler)
    {
        return addRoute!"post"(urlPattern, handler);
    }

    Route put(string urlPattern, RequestHandler handler)
    {
        return addRoute!"put"(urlPattern, handler);
    }

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

        // TODO: collect methods for error 405 messages
        //_routes.options.addRoute(urlPattern, &r.handleRequest);

        return r;
    }

    Response matchURL(RouteTreeNode* root, hstring url, Request request, Response response)
    {
        url = url.path;

        RouteMatchResult r = root.match(url);

        // error 405?
        if (r.requestHandler is null)
        {
            RouteMatchResult r405 = this._routes.options.match(url);

            // error 404?
            if (r.requestHandler is null)
                return this.handle404(request, response);

            return this.handle405(request, response);
        }

        // match
        return r.requestHandler(request, response, r.meta);
    }

    Response handle404(Request request, Response response)
    {
        if (_404 is null)
            return response.withStatus(404);

        return _404(request, response);
    }

    Response handle405(Request request, Response response)
    {
        // TODO: determine allowed methods

        if (_405 is null)
        {
            // TODO: set “Allow” header
            return response.withStatus(405);
        }

        return _405(request, response, []);
    }
}
