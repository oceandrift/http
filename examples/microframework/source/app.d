import oceandrift.http.microframework.app;

// listen on port 8080
static immutable listenOn = [
    makeSocketAddress("[::1]", 8080),     // IPv6 loopback address
    makeSocketAddress("127.0.0.1", 8080), // IPv4 loopback address
];

int main() @safe
{
    return runFramework(listenOn, delegate(Router router) {
        // define routes here

        // GET /
        router.get("/", delegate(Request, Response response) {
            // respond with "Hello world :)"
            response.body.write("Hello world :)");
            return response;
        });

        // GET /item/<placeholder>
        // GET /item/1
        // GET /item/2
        // GET /item/foo
        router.get("/item/:item-name", delegate(Request request, Response response, RouteMatchMeta meta) {
            // Access route parameter from route meta data
            hstring itemFromURI = meta.placeholders.get("item-name");

            // Respond echoing the item name
            response.body.write("Viewing item: " ~ itemFromURI);

            return response.withHeader!"Content-Type"("text/plain");
        });

        // GET /capture/<anything>
        // GET /capture/
        // GET /capture/foo
        // GET /capture/foo/bar
        router.get("/capture/*", delegate(Request request, Response response, RouteMatchMeta meta) {
            // Access route parameter from route meta data
            // There is only one for this route, so just access it by index
            hstring capturedFromURI = meta.placeholders[0].value;

            // Respond echoing the captured route component
            response.body.write(`Captured value: "` ~ capturedFromURI ~ '"');

            if (capturedFromURI == "ascii/art")
                response.body.write("\n\n      *      `'-\n     / \\   .\n    /   \\ / \\\n#################\n");

            return response.withHeader!"Content-Type"("text/plain; charset=US-ASCII");
        });

        // GET /uri-info
        // GET /uri-info?foo=bar
        router.get("/uri-info", delegate(Request request, Response response) {
            // raw request URI
            response.body.write("URI:\n\t");
            response.body.write(request.uri);

            // request URI decoded
            response.body.write("\nURI Decoded:\n\t");
            response.body.write(urlDecode(request.uri).toHString);

            // path string of request URI (“the string before the '?'”)
            response.body.write("\nPath:\n\t");
            response.body.write(request.uri.path);

            // query string of request URI (“the string after the '?'”)
            response.body.write("\nQuery:\n\t");
            response.body.write(request.uri.query);

            // return response with “content-type” + “server” headers
            return response
                .withHeader!"Content-Type"("text/plain; charset=UTF-8")
                .withHeader!"Server"("oceandrift/http");
        });

        // GET /form
        // GET /form?message=Hi
        router.get("/form", delegate(Request request, Response response) {
            // Print HTML page
            response.body.write(
                `<!DOCTYPE html><html><body><h1>oceandrift/http</h1><p>Microframework example</p>`
            );

            // check whether there’s a query parameter (aka “GET parameter”) named “message”
            hstring message = request.queryParams.get("message");
            if (message.length > 0)
            {
                // always escape user input!
                hstring messageEscaped = htmlEscape(urlDecode(message)).toHString;

                response.body.write(`
                    <section style="border:2px solid #000;background:#0FF;padding:1rem;margin:1rem 0">
                        <h2>User Message (via Query Parameter)</h2>
                        <pre style="color:#C00">`
                );
                response.body.write(messageEscaped);
                response.body.write(`</pre></section>`);
            }

            response.body.write(`
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
                    <input type="submit" value="Submit (POST; application/x-www-form-urlencoded)" />
                </form>
                <form method="POST" action="/form" enctype="multipart/form-data">
                    <label>
                        Message:
                        <input type="text" name="message" required />
                    </label>
                    <input type="submit" value="Submit (POST; multipart/form-data)" />
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
                response.body.write("Bad request, no or empty 'message' parameter");
                return response.withStatus(400);
            }

            response.body.write(
                `<!DOCTYPE html><html><body><h1>oceandrift/http</h1>
                <p>Microframework POST request example</p>
                    <h2>User Message (via Form Data)</h2>
                    <pre style="background:#EEE">`
            );

            // always escape user input!
            response.body.write(htmlEscape(message).toHString);

            response.body.write(`</pre></body></html>`);

            return response;
        });

        // GET /validate
        router.get("/validate", delegate(Request request, Response response) @safe {
            struct MyData
            {
                import oceandrift.validation.constraints;

                @isSet
                @notEmpty
                @isUnicode
                @maxLength(64)
                hstring message;

                @isSet
                long number;
            }

            // set content-type + content charset
            response.setHeader!"Content-Type"("text/html; charset=UTF-8");

            // write HTML
            response.body.write(
                `<!DOCTYPE html><html><body><h1>oceandrift/http</h1>
                <p>Microframework 'input validation' example</p>
                    <h2>Input Form</h2>
                    <form method="GET" action="/validate">
                        <label style="display: block">
                            Message
                            <textarea name="message"></textarea>
                        </label>
                        <label style="display: block">
                            Number
                            <input type="text" name="number" />
                        </label>
                        <input type="submit" value="Submit" />
                    </form>`);

            KeyValuePair[] queryParams = request.queryParamsData;

            // any query parameters provided?
            if (queryParams.length == 0)
            {
                // no query params, so no need to validate anything
                response.body.write(`</body></html>`);
                return response;
            }

            auto validationResult = queryParams.validateFormData!MyData();

            if (!validationResult.ok)
            {
                // validation failed
                // print a pretty error message
                response.body.write(`<h2 style="color: #F00">Validation failed</h2><p>Bad request</p><ul>`);
                foreach (e; validationResult.errors)
                    response.body.write(`<li>` ~ e.field ~ ": " ~ e.message ~ `</li>`);
                    // idup should be unnecessary once those are fixed:
                    // - https://issues.dlang.org/show_bug.cgi?id=23682
                    // - https://issues.dlang.org/show_bug.cgi?id=22916
                response.body.write(`</ul>`);

                return response.withStatus(400);
            }

            MyData validData = validationResult.data;

            response.body.write(`<h2>Validated User Message</h2><pre style="background:#EEE">`);
            response.body.write(htmlEscape(validData.message).toHString); // always escape non-HTML data
            response.body.write(`</pre><h2>Validated Number</h2><pre style="background:#EEE">`);
            response.body.write(htmlEscape(validData.number.to!string).toHString);
            response.body.write(`</pre></body></html>`);

            return response;
        });

        // GET /middleware
        router.get("/middleware",  delegate(Request request, Response response) {
            // regular request handler
            response.body.write("Main Request Handler\n");
            return response;
        }).add(delegate(Request request, Response response, MiddlewareNext next, RouteMatchMeta meta) {
            // middleware 1
            response.body.write("before 1\n");
            response = next(request, response);
            response.body.write("after 1\n");
            return response;
        }).add(delegate(Request request, Response response, MiddlewareNext next, RouteMatchMeta meta) {
            // middleware 2
            response.body.write("before 2\n");
            response = next(request, response);
            response.body.write("after 2\n");
            return response;
        });

        // GET /cookie
        router.get("/cookie",  delegate(Request request, Response response) {
            // get Cookie from request
            hstring cookieValue = request.getCookie("ExampleCookie");

            // no value set?
            if (cookieValue is null)
            {
                response.body.write("ExampleCookie was not set previously.");

                // set cookie
                response.setCookie(Cookie("ExampleCookie", "1234"));
                return response;
            }

            response.body.write("ExampleCookie value: " ~ cookieValue);
            return response;
        }).add(cookiesMiddleware);

        // Not Found (HTTP Status 404)
        router.notFoundHandler = delegate(Request request, Response response) {
            response.body.write("Not Found :(");
            return response;
        };
    });
}
