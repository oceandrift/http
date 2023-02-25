/+
    Microframework quickstart example app

    To build and execute it, just run the following command (in its root directory where the `dub.json` file lies):
    `dub -- -S 127.0.0.1:8080`

    `--` separates DUB args (left) from the applications args (right).
    The parameter `-S <host>:<port>` specifies the listening address to use.

    Feel free to replace `8080` with another port,
    or `127.0.0.1` with your desired listening address (e.g. `[::1]` for IPv6).
 +/

import oceandrift.http.microframework.app;

int main(string[] args) @safe
{
    return quickstart("oceandrift/http microframework", args, delegate(Router router) {
        // define routes here

        // GET /
        router.get("/", delegate(Request request, Response response) {
            // respond with "Hello world :)"
            response.body_.write("Hello world :)");
            return response;
        });

        // GET /<var>
        // e.g.
        //  GET /anything
        //  GET /something-else
        router.get("/:var", delegate(Request request, Response response, RouteMatchMeta meta) {
            response.body_.write(
                "URI:\t", request.uri, "\n",
                "Value:\t", meta.placeholders[0].value,
            );
            return response;
        });

    });
}
