import oceandrift.http.microframework.app;

// listen on port 8080
static immutable listenOn = [
    Socket(8080, "::1"), // IPv6 loopback address
    Socket(8080, "127.0.0.1"), // IPv4 loopback address
];

int main() @safe
{
    return runFramework(listenOn, delegate(Router router) {
        // define routes here

        // GET /
        router.get("/", delegate(Request, Response response) {
            // respond with "Hello world :)"
            response.body_.write("Hello world :)");
            return response;
        });

        // GET /item/<placeholder>
        // GET /item/1
        // GET /item/2
        // GET /item/foo
        router.get("/item/:item-name", delegate(Request request, Response response, RouteMatchMeta meta) {
            // Access route parameter from route meta data
            hstring itemFromURI = meta.placeholders.get("item-name");

            // Respond echo'ing the item name
            response.body_.write("Viewing item: ");
            response.body_.write(itemFromURI);

            return response.withHeader!"Content-Type"("text/plain");
        });

        // GET /uri-info
        // GET /uri-info?foo=bar
        router.get("/uri-info", delegate(Request request, Response response) {
            // raw request URI
            response.body_.write("URI:\n\t");
            response.body_.write(request.uri);

            // request URI decoded
            response.body_.write("\nURI Decoded:\n\t");
            response.body_.write(urlDecode(request.uri).toHString);

            // path string of request URI (“the string before the '?'”)
            response.body_.write("\nPath:\n\t");
            response.body_.write(request.uri.path);

            // query string of request URI (“the string after the '?'”)
            response.body_.write("\nQuery:\n\t");
            response.body_.write(request.uri.query);

            // return response with “content-type” + “server” headers
            return response
                .withHeader!"Content-Type"("text/plain; charset=UTF-8")
                .withHeader!"Server"("oceandrift/http");
        });

        // GET /form
        // GET /form?message=Hi
        router.get("/form", delegate(Request request, Response response) {
            // Print HTML page
            response.body_.write(
                `<!DOCTYPE html><html><body><h1>oceandrift/http</h1><p>Microframework example</p>`
            );

            // check whether there’s a query parameter (aka “GET parameter”) named “message”
            hstring message = request.queryParams.get("message");
            if (message.length > 0)
            {
                // always escape user input!
                hstring messageEscaped = htmlEscape(urlDecode(message)).toHString;

                response.body_.write(`
                    <section style="border:2px solid #000;background:#0FF;padding:1rem;margin:1rem 0">
                        <h2>User Message (via Query Parameter)</h2>
                        <pre style="color:#C00">`
                );
                response.body_.write(messageEscaped);
                response.body_.write(`</pre></section>`);
            }

            response.body_.write(`
                <form method="GET" action="/form">
                    <label>
                        Message:
                        <input type="text" name="message" required />
                    </label>
                    <input type="submit" value="Submit (GET)"/>
                </form>
                <form method="POST" action="/form">
                    <label>
                        Message:
                        <input type="text" name="message" required />
                    </label>
                    <input type="submit" value="Submit (POST)"/>
                </form>
                </body></html>`
            );

            // return response with “content-type” + “server” headers
            return response
                .withHeader!"Content-Type"("text/html; charset=UTF-8")
                .withHeader!"Server"("oceandrift/http");
        });

        // POST /form
        router.post("/form", delegate(Request request, Response response) {
            // check whether there’s a form data field (aka “POST parameter”) named “message”
            hstring message = request.formData.get("message");
            if (message.length == 0)
            {
                // no or empty “message” parameter
                response.body_.write("Bad request, no or empty “message” parameter");
                return response.withStatus(400);
            }

            response.body_.write(
                `<!DOCTYPE html><html><body><h1>oceandrift/http</h1>
                <p>Microframework POST request example</p>
                    <h2>User Message (via Form Data)</h2>
                    <pre style="background:#EEE">`
            );

            // always escape user input!
            response.body_.write(htmlEscape(message).toHString);

            response.body_.write(`</pre></body></html>`);

            return response;
        });
    });
}
