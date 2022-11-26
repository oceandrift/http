module oceandrift.http.server.server;

import oceandrift.http.message;
import oceandrift.http.server.messenger;
import std.datetime : dur;
import vibe.core.log;
import vibe.core.net;
import vibe.core.stream;

@safe:

/++
    Request Handler function signature
 +/
alias RequestHandler = Response delegate(Request request, Response response) @safe;

final class Server
{
@safe:
    private
    {
        TCPListener[] _listeners;
        RequestHandler _requestHandler;
    }

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
            connection.readTimeout = dur!"minutes"(3);

            while (!connection.empty)
            {
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

                Response response = _requestHandler(request, Response());

                // dfmt off
                response = (keepAlive)
                    ? response.withHeader!"Connection"("keep-alive")
                    : response.withHeader!"Connection"("close")
                ;
                // dfmt on

                try
                    sendResponse(connection, response);
                catch (Exception)
                    return;

                if (!keepAlive)
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
    return new Server(requestHandler);
}

public
{
    private import vibe.core.core;

    /++
        Run the application (and eventloop)
     +/
    alias runApplication = vibe.core.core.runApplication;
}
