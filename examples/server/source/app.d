import oceandrift.http.message;
import oceandrift.http.server.server;
import socketplate.server : SocketServer;

int main() @safe
{
    // create a new socketplate server
    auto server = new SocketServer();

    RequestHandler requestHandler = delegate(Request request, Response response) {
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
    };

    // listen on port 8080
    server.listenHTTP("[::1]:8080", requestHandler);     // IPv6 loopback address
    server.listenHTTP("127.0.0.1:8080", requestHandler); // IPv4 loopback address

    // bind to all ports
    server.bind();

    // run application
    return server.run();
}
