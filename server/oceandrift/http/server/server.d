module oceandrift.http.server.server;

import oceandrift.http.message;
import oceandrift.http.server.messenger;
import socketplate.address;
import socketplate.connection;
import socketplate.log;
import socketplate.server;
import std.datetime : dur;
import std.socket : Address;
import std.string : format;

@safe:

/++
    Request Handler function signature
 +/
alias RequestHandler = Response delegate(Request request, Response response) @safe;

struct HTTPServer
{
@safe:
    private
    {
        RequestHandler _requestHandler;
        Tunables _tunables;
    }

    public this(RequestHandler requestHandler, Tunables tunables) nothrow pure
    {
        _requestHandler = requestHandler;
    }

    private void serve(SocketConnection connection) nothrow
    {
        bool startedRequestParsing = false;

        try
        {
            while (!connection.empty)
            {
                startedRequestParsing = true;

                // The stack buffer breaks @safe-ty guarantees.
                // It would need `scope` which in it’s current state isn’t too handy
                // (→ “attribute soup”, “cannot take address […] indirection” on `const header = request.getHeader!"abc"();` …).
                //ubyte[1024 * 2] buffer;

                Request request;
                int parsed = -1;

                try
                    //parsed = parseRequest(connection, buffer, request);
                    parsed = parseRequest(connection, request);
                catch (Exception)
                    return;

                if (parsed < 0) // Bad Header
                {
                    enum rp = getReasonPhrase(400);
                    sendResponse(connection, 400, rp);
                    return;
                }
                else if (parsed > 0) // error code
                {
                    try
                        sendResponse(connection, parsed, getReasonPhrase(parsed));
                    catch (Exception)
                        return;
                    return;
                }

                immutable bool keepAlive = request.isKeepAlive;

                auto response = Response(200);
                try
                {
                    response = _requestHandler(request, response);
                }
                catch (Exception ex)
                {
                    logException(ex, "Unhandled Exception thrown in request handler");
                    response = Response(500, getReasonPhrase(500));
                }

                // dfmt off
                response.setHeader!"Connection"(
                    (keepAlive)
                        ? "keep-alive"
                        : "close"
                );
                // dfmt on

                try
                    sendResponse(connection, response);
                catch (Exception)
                    return;

                if (!keepAlive)
                    return;
            }
        }
        catch (SocketTimeoutException ex)
        {
            // just a dead keep-alive connection?
            if (!startedRequestParsing)
                return;

            // timeout → send an error 408
            try
                return sendResponse(connection, 408, getReasonPhrase(408));
            catch (Exception ex)
                return logException(ex, "408"); // log, close connection and forget about it
        }
        catch (Exception ex)
        {
            logException(ex, "Unhandled Exception caught in Server.serve()");
            return;
        }
        finally
        {
            connection.close();
        }
    }
}

/++
    Registers a new TCP listener
 +/
void listenHTTP(SocketServer server, Address address, RequestHandler requestHandler, Tunables tunables = Tunables())
{
    logInfo("oceandrift/http: will listen on http://" ~ address.toString);
    return server.listenTCP(address, makeHTTPServer(requestHandler, tunables));
}

/// ditto
void listenHTTP(
    SocketServer server,
    SocketAddress listenOn,
    RequestHandler requestHandler,
    Tunables tunables = Tunables()
)
{
    final switch (listenOn.type) with (SocketAddress.Type)
    {
    case invalid:
        assert(false);

    case unixDomain:
        logInfo(
            format!"oceandrift/http: will listen on unix://%s"(listenOn.address)
        );
        break;

    case ipv4:
        logInfo(
            format!"oceandrift/http: will listen on http://%s:%d"(listenOn.address, listenOn.port)
        );
        break;

    case ipv6:
        logInfo(
            format!"oceandrift/http: will listen on http://[%s]:%d"(listenOn.address, listenOn.port)
        );
        break;
    }
    return server.listenTCP(listenOn, makeHTTPServer(requestHandler, tunables));
}

/// ditto
void listenHTTP(SocketServer server, string listenOn, RequestHandler requestHandler, Tunables tunables = Tunables())
{
    scope (success)
        logInfo("oceandrift/http: will listen on http://" ~ listenOn);
    return server.listenTCP(listenOn, makeHTTPServer(requestHandler, tunables));
}

ConnectionHandler makeHTTPServer(RequestHandler requestHandler, Tunables tunables) nothrow
{
    HTTPServer* httpServer = new HTTPServer(requestHandler, tunables);
    return &httpServer.serve;
}

///
struct Tunables
{
}
