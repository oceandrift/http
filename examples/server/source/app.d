import oceandrift.http.message;
import oceandrift.http.server.server;
import vibe.core.log;

int main() @safe
{
    Server server = boot(delegate(Request request, Response response) {
        //logInfo("%s", request);

        if (request.uri != "/")
            return response.withStatus(404);

        // let’s respond
        response.body_.write("Hello world :D");

        //return response;

        // print request headers to response
        response.body_.write(
            "\n\n\n",
            "Request Headers:\n",
            "================\n",
        );
        foreach (Header h; request.headers)
            foreach (value; h.values)
                response.body_.write(h.name, ": ", value, "\n");

        // return response with “content-type” + “server” headers
        return response
            .withHeader!"Content-Type"("text/plain; charset=UTF-8")
            .withHeader!"Server"("oceandrift/http");
    });

    // listen on port 8080
    server.listen(8080, "::1"); // IPv6 loopback address
    server.listen(8080, "127.0.0.1"); // IPv4 loopback address

    // shutdown cleanly on exit
    scope (exit)
        server.shutdown();

    // run application
    return runApplication();
}
