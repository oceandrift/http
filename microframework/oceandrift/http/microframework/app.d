module oceandrift.http.microframework.app;

import core.runtime : Runtime;
import oceandrift.http.microframework.router;
import oceandrift.http.server;

public import oceandrift.http.message : hbuffer, hstring, Request, Response;
public import oceandrift.http.microframework.cookies;
public import oceandrift.http.microframework.form;
public import oceandrift.http.microframework.html;
public import oceandrift.http.microframework.kvp;
public import oceandrift.http.microframework.middleware;
public import oceandrift.http.microframework.router : Router, RoutedRequestHandler, RouteMatchMeta;
public import oceandrift.http.microframework.uri;
public import oceandrift.http.microframework.validation;
public import socketplate.address;
public import socketplate.server : SocketServer, SocketServerTunables;
public import socketplate.log;
public import std.conv : to;

@safe:

///
alias RouterConfigDelegate = void delegate(Router) @safe;

/++
    Straightforward microframework app bootstrapper
    
    Call this function to start-up your oceandrift/http microframework app in a convenient way.

    ---
    import oceandrift.http.microframework.app;
    
    static immutable listenOn = [
        Socket(8080, "::1"),       // IPv6 loopback, port 8080
        Socket(8080, "127.0.0.1"), // IPv4 loopback, port 8080
    ];

    int main() @safe
    {
        return runFramework(listenOn, delegate(ref Router router) {
            // define your routes here, e.g.
            router.get("/", /* … */);
        });
    }
    ---
 +/
int runFramework(
    const SocketAddress[] listenOn,
    RouterConfigDelegate configureRouter,
    Tunables tunables = Tunables(),
    SocketServerTunables socketServerTunables = SocketServerTunables(),
)
in (configureRouter !is null)
{
    Router router;
    RequestHandler requestHandler = makeRouterRequestHandler(router);

    auto server = new SocketServer(socketServerTunables);
    foreach (SocketAddress socketAddr; listenOn)
        server.listenHTTP(socketAddr, requestHandler, tunables);

    configureRouter(router);

    server.bind();

    // run application
    return server.run();
}

int quickstart(
    string appName,
    string[] args,
    RouterConfigDelegate configureRouter,
    Tunables tunables = Tunables(),
    string[] defaultListeningAddresses = null,
    SocketServerTunables socketServerTunables = SocketServerTunables(),
)
in (configureRouter !is null)
{
    import socketplate.app;

    Router router;
    ConnectionHandler connectionHandler = makeHTTPServer(makeRouterRequestHandler(router), tunables);

    configureRouter(router);

    return runSocketplateAppTCP(
        appName,
        args,
        connectionHandler,
        defaultListeningAddresses,
        socketServerTunables,
    );
}
