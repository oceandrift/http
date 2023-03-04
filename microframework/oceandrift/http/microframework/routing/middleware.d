module oceandrift.http.microframework.routing.middleware;

import oceandrift.http.microframework.routing.router : RoutedRequestHandler;

public import oceandrift.http.message : Request, Response;
public import oceandrift.http.microframework.routing.router : RouteMatchMeta;
public import oceandrift.http.server : RequestHandler;

@safe:

///
alias MiddlewareRequestHandler = Response delegate(
    Request request,
    Response response,
    MiddlewareNext next,
    RouteMatchMeta meta,
) @safe;

/++
    ---
    delegate(Request request, Response response, MiddlewareNext next, RouteMatchMeta) @safe {
        // […] do something before

        // call “next” request handler
        response = next(request, response);

        // […] do something after

        return response;
    }
    ---
 +/
struct MiddlewareNext
{
@safe:

    private
    {
        size_t _n;
        MiddlewareRequestHandler[] _middleware;
        RequestHandler _next;
        RoutedRequestHandler _nextR;
        RouteMatchMeta _meta;
    }

    @disable
    private this();

    package(oceandrift.http.microframework) this(
        MiddlewareRequestHandler[] middleware,
        RequestHandler next,
        RoutedRequestHandler nextR,
        RouteMatchMeta meta,
    )
    {
        _middleware = middleware;
        _next = next;
        _nextR = nextR;
        _meta = meta;
    }

    ///
    public Response opCall(Request request, Response response)
    {
        if (_middleware.length == 0)
            return (_next !is null) ? _next(request, response) : _nextR(request, response, _meta);

        immutable mw = _middleware[0];
        _middleware = _middleware[1 .. $];

        return mw(request, response, this, _meta);
    }
}
