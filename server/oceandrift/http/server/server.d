module oceandrift.http.server.server;

import oceandrift.http.message;
import oceandrift.http.server.messenger;
import std.datetime : dur;
import vibe.core.log;
import vibe.core.net;
import vibe.core.stream;

@safe:

alias RequestHandler = Response delegate(scope Request request, scope Response response) @safe;

struct Server
{
@safe:
    private
    {
        TCPListener[] _listeners;
        RequestHandler _requestHandler;
    }

    @disable this();

    public this(RequestHandler requestHandler) nothrow pure @nogc
    {
        _requestHandler = requestHandler;
    }

    void listen(ushort port = 8080, string address = "::1")
    in (_requestHandler !is null)
    {
        TCPListener listener = listenTCP(port, &this.serve, address);
        _listeners ~= listener;

        logInfo("oceandrift/http: will listen on http://%s", listener.bindAddress.toString);
    }

    void shutdown()
    {
        logDiagnostic("oceandrift/http: shutdown()");

        foreach (TCPListener listener; _listeners)
            listener.stopListening();

        _listeners = [];
    }

    private void serve(TCPConnection connection) nothrow
    {
        try
        {
            connection.tcpNoDelay = true;
            connection.readTimeout = dur!"seconds"(10);

            while (!connection.empty)
            {
                ubyte[256] buffer;
                Request request;
                int parsed = -1;

                try
                    parsed = parseRequest(connection, buffer, request);
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

                Response response = _requestHandler(request, Response());
                sendResponse(connection, response);

                // TODO: Keep Alived

                return;
            }
        }
        catch (ReadTimeoutException ex)
        {
            try
            {
                sendResponse(connection, 408, getReasonPhrase(408));
            }
            catch (Exception ex)
            {
                assert(0, "TODO");
            }
            return;
        }
        catch (Exception ex)
        {
            logException(ex, "serve()");
            return;
        }
        finally
        {
            connection.close();
        }
    }
}

///
Server boot(RequestHandler requestHandler) nothrow
{
    return Server(requestHandler);
}

///
int run()
{
    import vibe.core.core;

    logDiagnostic("oceandrift/http: run()");
    return runApplication();
}
