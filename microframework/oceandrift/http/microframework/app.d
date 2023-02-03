module oceandrift.http.microframework.app;

import oceandrift.http.microframework.router;
import oceandrift.http.server;

public import oceandrift.http.message : hbuffer, hstring, Request, Response;
public import oceandrift.http.microframework.form;
public import oceandrift.http.microframework.html;
public import oceandrift.http.microframework.kvp;
public import oceandrift.http.microframework.router : MiddlewareNext, Router, RoutedRequestHandler, RouteMatchMeta;
public import oceandrift.http.microframework.uri;
public import oceandrift.http.microframework.validation;
public import std.conv : to;

@safe:

///
struct Socket
{
    /// Port number
    ushort port;

    /// Address (e.g. IPv4 address, IPv6 address)
    string address;
}

///
alias RouterConfigDelegate = void delegate(Router router) @safe;

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
int runFramework(const Socket[] listenOn, RouterConfigDelegate configureRouter)
in (configureRouter !is null)
{
    Router router;
    Server server = bootWithRouter(router);

    foreach (Socket socket; listenOn)
        server.listen(socket.port, socket.address);

    configureRouter(router);

    // shutdown cleanly on exit
    scope (exit)
        server.shutdown();

    // run application
    return runApplication();
}
