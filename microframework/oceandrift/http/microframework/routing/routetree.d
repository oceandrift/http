/++
    Route tree implementation

    This module implements a simple tree-structure for storing routes.

    $(NOTE
        If you just want to use the framework and aren’t looking forward to work on the routing implementation (or your own),
        feel free to skip reading this module’s documentation.
    )

    This tree is built using [RouteTreeNode] nodes connected via [RouteTreeLink]s.
    The URL is composed through “components” along the [RouteTreeLinks].

    The tree is built upon a “root” node.
    Nodes are added by calling [addRoute] and passing along the root node, the target URL and a request handler.
    URLs are specified as absolute locations starting with a slash (`/`).

    Routing is straightforward as well:
    Call [match] to get the request handler registered for the provided URL.

    Supports $(B route placeholders) (“variables”).
    They start with a colon (`:`) and are terminated with a slash (`/`); the slash ends up as part of the URL.
    When a route is supposed to end with a placeholder, omit the trailling slash (`/`).

    $(TIP
        Route placeholders are called $(B wildcards) internally.
    )

    Alternatively, also supports $(B deep wildcards).
    They are written as asterisk (`*`) and capture everything to the end of the URL.
    These can only exist at the end of a route and cannot overlap with regular $(I route placeholders).
 +/
module oceandrift.http.microframework.routing.routetree;

import std.string : indexOf;
import oceandrift.http.message : hstring, Request, Response;
import oceandrift.http.microframework.kvp;

@safe:

alias RoutedRequestHandler = Response delegate(
    Request request,
    Response response,
    RouteMatchMeta meta,
) @safe;

///
struct RouteTreeLink(TLeaf)
{
    string component = null;
    RouteTreeNode!TLeaf* node;
}

struct RouteWildcard(TLeaf)
{
    bool deep = false;
    RouteTreeLink!TLeaf link;
}

///
struct RouteTreeNode(TLeaf = RoutedRequestHandler)
{
    TLeaf requestHandler;

    RouteTreeLink!(TLeaf)[] branches;
    RouteWildcard!TLeaf wildcard;
}

///
void addRoute(TLeaf)(RouteTreeNode!TLeaf* root, string url, TLeaf requestHandler)
in (root !is null)
in (url[0] == '/')
{
    return addRouteTreeNode(root, url[1 .. $], requestHandler);
}

private void addRouteTreeNode(TLeaf)(RouteTreeNode!TLeaf* tree, string url, TLeaf requestHandler)
{
    if (url.length == 0)
    {
        assert(tree.requestHandler is null, "Duplicate route");

        tree.requestHandler = requestHandler;
        return;
    }

    // deep wildcard?
    if (url[0] == '*')
    {
        assert(url.length == 1, "Deep wildcard must be at the end of a route");
        assert(tree.wildcard.link.node is null, "Cannot insert deep wildcard where already is a route placeholders");

        tree.wildcard.deep = true;
        tree.wildcard.link.component = "*";
        tree.wildcard.link.node = new RouteTreeNode!TLeaf(requestHandler);
        return;
    }

    // placeholder?
    if (url[0] == ':')
    {
        url = url[1 .. $];

        immutable ptrdiff_t endOfWildcard = url.indexOf('/');

        if (tree.wildcard.link.node is null) // insert
        {
            tree.wildcard.link.node = new RouteTreeNode!TLeaf();

            if (endOfWildcard < 0) // end of url reached
            {
                tree.wildcard.link.component = url[0 .. $];
                tree.wildcard.link.node.requestHandler = requestHandler;
                return;
            }

            tree.wildcard.link.component = url[0 .. endOfWildcard];
            return addRouteTreeNode(tree.wildcard.link.node, url[endOfWildcard .. $], requestHandler);
        }

        // exists (no direct insert)

        string component;

        if (endOfWildcard < 0)
        {
            component = url[0 .. $];
            url = "";
        }
        else
        {
            component = url[0 .. endOfWildcard];
            url = url[endOfWildcard .. $];
        }

        assert(!tree.wildcard.deep, "Cannot insert a route placeholder where already is a deep wildcard");

        // dfmt off
        assert(
            (
                (component == tree.wildcard.link.component)
                || (component == "")
                || (tree.wildcard.link.component == "")
            ),
            "Ambiguously named route placeholder: `"
                ~ component
                ~ "` (already knowns as: `" ~ tree.wildcard.link.component ~ "`)"
        );
        // dfmt on

        tree.wildcard.link.component = component;
        return addRouteTreeNode(tree.wildcard.link.node, url, requestHandler);
    }

    foreach (ref branch; tree.branches)
    {
        if (branch.component[0] != url[0])
            continue;

        string shorter, longer;
        if (branch.component.length > url.length)
        {
            shorter = url;
            longer = branch.component;
        }
        else
        {
            shorter = branch.component;
            longer = url;
        }

        ptrdiff_t idxSplit = 0;
        for (size_t i = 1; i < shorter.length; ++i) // start @1, because 0 is known to match
        {
            if (shorter[i] != longer[i])
            {
                idxSplit = i;
                break;
            }
        }

        if (idxSplit == 0) // exact match
        {
            if (branch.component.length > url.length)
            {
                auto replacementNode = new RouteTreeNode!TLeaf(requestHandler, [
                        RouteTreeLink!TLeaf(branch.component[shorter.length .. $], branch.node) // link to existing node
                    ]
                );

                branch.component = branch.component[0 .. shorter.length];
                branch.node = replacementNode;

                return;
            }
            else
            {
                return addRouteTreeNode(branch.node, url[shorter.length .. $], requestHandler);
            }
        }

        // mismatch found, → split

        auto replacementNode = new RouteTreeNode!TLeaf(null, [
                RouteTreeLink!TLeaf(branch.component[idxSplit .. $], branch.node) // link to existing node
            ]
        );

        addRouteTreeNode(replacementNode, url[idxSplit .. $], requestHandler);
        branch.component = url[0 .. idxSplit];
        branch.node = replacementNode;

        return;
    }

    // insert

    ptrdiff_t nextWildcard = url.indexOf(':');
    if (nextWildcard < 0)
        nextWildcard = url.indexOf('*');

    if (nextWildcard >= 0)
    {
        auto beforeWildcard = new RouteTreeNode!TLeaf();
        addRouteTreeNode(beforeWildcard, url[nextWildcard .. $], requestHandler);
        tree.branches ~= RouteTreeLink!TLeaf(url[0 .. nextWildcard], beforeWildcard);
        return;
    }

    // no wildcard left, simple insert
    tree.branches ~= RouteTreeLink!TLeaf(url, new RouteTreeNode!TLeaf(requestHandler));
    return;
}

unittest
{
    import oceandrift.http.message;

    // dfmt off
    RoutedRequestHandler rh0 = delegate(Request, Response r, RouteMatchMeta) { return r; };
    RoutedRequestHandler rh1 = delegate(Request, Response r, RouteMatchMeta) { return r.withStatus(201); };
    RoutedRequestHandler rh2 = delegate(Request, Response r, RouteMatchMeta) { return r.withStatus(202); };
    RoutedRequestHandler rh3 = delegate(Request, Response r, RouteMatchMeta) { return r.withStatus(203); };
    // dfmt on

    auto routerRoot = new RouteTreeNode!RoutedRequestHandler();

    routerRoot.addRoute("/hello", rh0);
    assert(routerRoot.requestHandler is null);
    assert(routerRoot.wildcard.link.node is null);
    assert(routerRoot.branches.length == 1);
    assert(routerRoot.branches[0].component == "hello");
    assert(routerRoot.branches[0].node.requestHandler == rh0);
    assert(routerRoot.branches[0].node.branches.length == 0);
    assert(routerRoot.branches[0].node.wildcard.link.node is null);

    routerRoot.addRoute("/world", rh1);
    assert(routerRoot.requestHandler is null);
    assert(routerRoot.wildcard.link.node is null);
    assert(routerRoot.branches.length == 2);
    assert(routerRoot.branches[0].component == "hello");
    assert(routerRoot.branches[0].node.requestHandler == rh0);
    assert(routerRoot.branches[0].node.branches.length == 0);
    assert(routerRoot.branches[0].node.wildcard.link.node is null);
    assert(routerRoot.branches[1].component == "world");
    assert(routerRoot.branches[1].node.requestHandler == rh1);
    assert(routerRoot.branches[1].node.branches.length == 0);
    assert(routerRoot.branches[1].node.wildcard.link.node is null);

    routerRoot.addRoute("/hello-world", rh2);
    assert(routerRoot.requestHandler is null);
    assert(routerRoot.wildcard.link.node is null);
    assert(routerRoot.branches.length == 2);
    assert(routerRoot.branches[0].component == "hello");
    assert(routerRoot.branches[0].node.requestHandler == rh0);
    assert(routerRoot.branches[0].node.branches.length == 1);
    assert(routerRoot.branches[0].node.branches[0].component == "-world");
    assert(routerRoot.branches[0].node.branches[0].node.requestHandler == rh2);
    assert(routerRoot.branches[0].node.branches[0].node.branches.length == 0);
    assert(routerRoot.branches[0].node.branches[0].node.wildcard.link.node is null);

    routerRoot.addRoute("/hello_there", rh1);
    assert(routerRoot.requestHandler is null);
    assert(routerRoot.wildcard.link.node is null);
    assert(routerRoot.branches.length == 2);
    assert(routerRoot.branches[0].component == "hello");
    assert(routerRoot.branches[0].node.requestHandler == rh0);
    assert(routerRoot.branches[0].node.branches.length == 2);
    assert(routerRoot.branches[0].node.branches[0].component == "-world");
    assert(routerRoot.branches[0].node.branches[0].node.requestHandler == rh2);
    assert(routerRoot.branches[0].node.branches[0].node.branches.length == 0);
    assert(routerRoot.branches[0].node.branches[0].node.wildcard.link.node is null);
    assert(routerRoot.branches[0].node.branches[1].component == "_there");
    assert(routerRoot.branches[0].node.branches[1].node.requestHandler == rh1);
    assert(routerRoot.branches[0].node.branches[1].node.branches.length == 0);
    assert(routerRoot.branches[0].node.branches[1].node.wildcard.link.node is null);

    routerRoot.addRoute("/hello_you", rh3);
    assert(routerRoot.branches[0].component == "hello");
    assert(routerRoot.branches[0].node.requestHandler == rh0);
    assert(routerRoot.branches[0].node.branches.length == 2);
    assert(routerRoot.branches[0].node.branches[1].component == "_");
    assert(routerRoot.branches[0].node.branches[1].node.requestHandler is null);
    assert(routerRoot.branches[0].node.branches[1].node.wildcard.link.node is null);
    assert(routerRoot.branches[0].node.branches[1].node.branches.length == 2);
    assert(routerRoot.branches[0].node.branches[1].node.branches[0].component == "there");
    assert(routerRoot.branches[0].node.branches[1].node.branches[0].node.requestHandler == rh1);
    assert(routerRoot.branches[0].node.branches[1].node.branches[1].component == "you");
    assert(routerRoot.branches[0].node.branches[1].node.branches[1].node.requestHandler == rh3);

    routerRoot.addRoute("/world/:no", rh3);
    assert(routerRoot.branches.length == 2);
    assert(routerRoot.branches[1].node.branches.length == 1);
    assert(routerRoot.branches[1].node.wildcard.link.node is null);
    assert(routerRoot.branches[1].node.branches[0].component == "/");
    assert(routerRoot.branches[1].node.branches[0].node.requestHandler is null);
    assert(routerRoot.branches[1].node.branches[0].node.branches.length == 0);
    assert(routerRoot.branches[1].node.branches[0].node.wildcard.link.component == "no");
    assert(routerRoot.branches[1].node.branches[0].node.wildcard.link.node.wildcard.link.node is null);
    assert(routerRoot.branches[1].node.branches[0].node.wildcard.link.node.branches.length == 0);
    assert(routerRoot.branches[1].node.branches[0].node.wildcard.link.node.requestHandler == rh3);

    routerRoot.addRoute("/world/:no/asdf", rh2);
    assert(routerRoot.branches[1].node.branches[0].node.wildcard.link.component == "no");
    assert(routerRoot.branches[1].node.branches[0].node.branches.length == 0);
    assert(routerRoot.branches[1].node.branches[0].node.wildcard.link.node.wildcard.link.node is null);
    assert(routerRoot.branches[1].node.branches[0].node.wildcard.link.node.branches.length == 1);
    assert(
        routerRoot.branches[1].node.branches[0].node.wildcard.link.node.branches[0].component == "/asdf"
    );
    assert(
        routerRoot.branches[1].node.branches[0].node.wildcard.link.node
            .branches[0]
            .node.requestHandler == rh2
    );

    routerRoot.addRoute("/world/:no/", rh1);
    assert(routerRoot.branches.length == 2);
    assert(routerRoot.branches[1].node.branches.length == 1);
    assert(routerRoot.branches[1].node.branches[0].node.wildcard.link.node.branches.length == 1);
    assert(
        routerRoot.branches[1].node.branches[0].node.wildcard.link.node.branches[0].component == "/");
    assert(
        routerRoot.branches[1].node.branches[0].node.wildcard.link.node
            .branches[0]
            .node.branches.length == 1
    );
    assert(
        routerRoot.branches[1].node.branches[0].node.wildcard.link.node
            .branches[0].node.branches[0].component == "asdf"
    );
    assert(
        routerRoot.branches[1].node.branches[0].node.wildcard.link.node
            .branches[0].node.branches[0].node.requestHandler == rh2
    );
    assert(
        routerRoot.branches[1].node.branches[0].node.wildcard.link.node
            .branches[0].node.requestHandler == rh1
    );
    assert(
        routerRoot.branches[1].node.branches[0].node.wildcard.link.node
            .branches[0].node.wildcard.link.node is null
    );

    routerRoot.addRoute("/foo/:var/", rh2);
    assert(routerRoot.branches[2].component == "foo/");
    assert(routerRoot.branches[2].node.requestHandler is null);
    assert(routerRoot.branches[2].node.wildcard.deep == false);
    assert(routerRoot.branches[2].node.wildcard.link.component == "var");
    assert(routerRoot.branches[2].node.wildcard.link.node !is null);
    assert(routerRoot.branches[2].node.wildcard.link.node.requestHandler is null);
    assert(routerRoot.branches[2].node.wildcard.link.node.branches.length == 1);
    assert(routerRoot.branches[2].node.wildcard.link.node.branches[0].component == "/");
    assert(routerRoot.branches[2].node.wildcard.link.node.branches[0].node.requestHandler == rh2);

    routerRoot.addRoute("/foo/:var", rh0);
    assert(routerRoot.branches[2].node.wildcard.link.node.branches[0].node.requestHandler == rh2);
    assert(routerRoot.branches[2].node.wildcard.link.node.requestHandler == rh0);

    routerRoot.addRoute("/abc", rh0);
    assert(routerRoot.branches[3].component == "abc");
    assert(routerRoot.branches[3].node.requestHandler == rh0);
    routerRoot.addRoute("/abc/def", rh1);
    assert(routerRoot.branches[3].component == "abc");
    assert(routerRoot.branches[3].node.branches.length == 1);
    assert(routerRoot.branches[3].node.branches[0].component == "/def");
    assert(routerRoot.branches[3].node.branches[0].node.requestHandler == rh1);
    routerRoot.addRoute("/abc/", rh2);
    assert(routerRoot.branches[3].node.branches.length == 1);
    assert(routerRoot.branches[3].node.branches[0].component == "/");
    assert(routerRoot.branches[3].node.branches[0].node.requestHandler == rh2);
    assert(routerRoot.branches[3].node.branches[0].node.branches.length == 1);
    assert(routerRoot.branches[3].node.branches[0].node.branches[0].node.requestHandler == rh1);
    assert(routerRoot.branches[3].node.branches[0].node.branches[0].component == "def");
    routerRoot.addRoute("/abc/ghi", rh3);
    assert(routerRoot.branches[3].node.branches[0].node.branches.length == 2);
    assert(routerRoot.branches[3].node.branches[0].node.branches[0].node.requestHandler == rh1);
    assert(routerRoot.branches[3].node.branches[0].node.branches[0].component == "def");
    assert(routerRoot.branches[3].node.branches[0].node.branches[1].node.requestHandler == rh3);
    assert(routerRoot.branches[3].node.branches[0].node.branches[1].component == "ghi");
    routerRoot.addRoute("/abc/jkl", rh0);
    assert(routerRoot.branches[3].node.branches[0].node.branches.length == 3);
    assert(routerRoot.branches[3].node.branches[0].node.branches[0].node.requestHandler == rh1);
    assert(routerRoot.branches[3].node.branches[0].node.branches[0].component == "def");
    assert(routerRoot.branches[3].node.branches[0].node.branches[1].node.requestHandler == rh3);
    assert(routerRoot.branches[3].node.branches[0].node.branches[1].component == "ghi");
    assert(routerRoot.branches[3].node.branches[0].node.branches[2].node.requestHandler == rh0);
    assert(routerRoot.branches[3].node.branches[0].node.branches[2].component == "jkl");

    assert(routerRoot.branches[3].node.branches[0].node.branches[0].node.branches.length == 0);
    routerRoot.addRoute("/abc/def/mno", rh3);
    assert(routerRoot.branches[3].node.branches[0].node.branches[0].component == "def");
    assert(routerRoot.branches[3].node.branches[0].node.branches[0].node.requestHandler == rh1);
    assert(routerRoot.branches[3].node.branches[0].node.branches[0].node.branches.length == 1);
    assert(
        routerRoot.branches[3].node.branches[0].node.branches[0].node
            .branches[0].node.requestHandler == rh3
    );
    assert(
        routerRoot.branches[3].node.branches[0].node.branches[0].node.branches[0].component == "/mno"
    );

    routerRoot.addRoute("/:1/:2", rh0);
    assert(routerRoot.wildcard.link.node !is null);
    assert(routerRoot.wildcard.link.component == "1");
    assert(routerRoot.wildcard.link.node.branches[0].component == "/");
    assert(routerRoot.wildcard.link.node.branches[0].node.wildcard.link.node !is null);
    assert(routerRoot.wildcard.link.node.branches[0].node.wildcard.link.component == "2");
    assert(routerRoot.wildcard.link.node.branches[0].node.wildcard.link.node.requestHandler == rh0);
    routerRoot.addRoute("/:1/:2/gulaschsuppm", rh1);
    assert(
        routerRoot.wildcard.link.node.branches[0].node.wildcard.link.node
            .branches[0].component == "/gulaschsuppm"
    );
    assert(
        routerRoot.wildcard.link.node.branches[0].node.wildcard.link.node
            .branches[0]
            .node.requestHandler == rh1
    );

    routerRoot.addRoute("/deep/*", rh3);
    assert(routerRoot.branches[4].node !is null);
    assert(routerRoot.branches[4].component == "deep/", routerRoot.branches[4].component);
    assert(routerRoot.branches[4].node.wildcard.link.node !is null);
    assert(routerRoot.branches[4].node.wildcard.deep == true);
    assert(routerRoot.branches[4].node.wildcard.link.component == "*");
    assert(routerRoot.branches[4].node.wildcard.link.node.requestHandler == rh3);
    assert(routerRoot.branches[4].node.wildcard.link.node.wildcard.link.node is null);
    assert(routerRoot.branches[4].node.wildcard.link.node.branches.length == 0);
}

@system unittest
{
    import std.exception : assertThrown;
    import oceandrift.http.message;

    RoutedRequestHandler rh0 = delegate(Request, Response r, RouteMatchMeta) {
        return r;
    };
    auto routerRoot = new RouteTreeNode!RoutedRequestHandler();

    assertThrown!Error(routerRoot.addRoute(":id/", rh0));

    routerRoot.addRoute("/:foo", rh0);
    assertThrown!Error(routerRoot.addRoute("/:bar", rh0));

    routerRoot.addRoute("/a/:foo/x", rh0);
    assertThrown!Error(routerRoot.addRoute("/a/:bar/y", rh0));

    routerRoot.addRoute("/2000", rh0);
    assertThrown!Error(routerRoot.addRoute("/2000", rh0));
}

///
struct RouteMatchMeta
{
    ///
    KeyValuePair[] placeholders;

    ///
    static typeof(this) merge(RouteMatchMeta a, RouteMatchMeta b)
    {
        return RouteMatchMeta(a.placeholders ~ b.placeholders);
    }
}

struct RouteMatchResult(TLeaf)
{
    TLeaf requestHandler;
    RouteMatchMeta meta;
}

///
RouteMatchResult!TLeaf match(TLeaf)(RouteTreeNode!TLeaf* root, hstring url)
{
    if (url.length == 0)
        return RouteMatchResult!TLeaf(null);

    if (url[0] != '/')
        return RouteMatchResult!TLeaf(null);

    RouteMatchResult!TLeaf output;
    output.requestHandler = matchRoute!TLeaf(root, url[1 .. $], output.meta);
    return output;
}

private TLeaf matchRoute(TLeaf)(RouteTreeNode!TLeaf* tree, hstring url, ref RouteMatchMeta routeMatchMeta)
{
    // direct match?
    if (url.length == 0)
    {
        // no direct request handler?
        if (tree.requestHandler is null)
        {
            // maybe a deep wildcard?
            if ((tree.wildcard.link.node !is null) && tree.wildcard.deep)
            {
                routeMatchMeta.placeholders ~= KeyValuePair(tree.wildcard.link.component, url);
                return tree.wildcard.link.node.requestHandler;
            }
        }

        return tree.requestHandler;
    }

    // matching branches?
    foreach (branch; tree.branches)
    {
        if (branch.component.length > url.length) // branch can’t match
            continue;

        if (branch.component != url[0 .. branch.component.length]) // branch mismatches
            continue;

        return matchRoute(branch.node, url[branch.component.length .. $], routeMatchMeta);
    }

    // wildcard match?
    if (tree.wildcard.link.node !is null)
    {
        ptrdiff_t endOfWildcard;

        if (tree.wildcard.deep)
        {
            endOfWildcard = url.length;
        }
        else
        {
            endOfWildcard = url.indexOf('/');

            if (endOfWildcard < 0)
                endOfWildcard = url.length;
        }

        routeMatchMeta.placeholders ~= KeyValuePair(tree.wildcard.link.component, url[0 .. endOfWildcard]);
        return matchRoute(tree.wildcard.link.node, url[endOfWildcard .. $], routeMatchMeta);
    }

    // no match
    return null;
}

unittest
{
    import oceandrift.http.message;

    // dfmt off
    RoutedRequestHandler rhRoot = delegate(Request, Response r, RouteMatchMeta) { return r; };
    RoutedRequestHandler rhHello = delegate(Request, Response r, RouteMatchMeta) { return r; };
    RoutedRequestHandler rhHelloWorld = delegate(Request, Response r, RouteMatchMeta) { return r; };
    RoutedRequestHandler rhHel = delegate(Request, Response r, RouteMatchMeta) { return r; };
    RoutedRequestHandler rhItems = delegate(Request, Response r, RouteMatchMeta) { return r; };
    RoutedRequestHandler rhItems2 = delegate(Request, Response r, RouteMatchMeta) { return r; };
    RoutedRequestHandler rhItemN = delegate(Request, Response r, RouteMatchMeta) { return r; };
    RoutedRequestHandler rhItemNOwner = delegate(Request, Response r, RouteMatchMeta) { return r; };
    RoutedRequestHandler rhItemNOwnerPetN = delegate(Request, Response r, RouteMatchMeta) { return r; };
    RoutedRequestHandler rhVisitors = delegate(Request, Response r, RouteMatchMeta) { return r; };
    RoutedRequestHandler rhHelloDeepWildcard = delegate(Request, Response r, RouteMatchMeta) { return r; };
    // dfmt on

    auto routerRoot = new RouteTreeNode!RoutedRequestHandler(rhRoot);

    routerRoot.addRoute("/hello", rhHello);
    routerRoot.addRoute("/hello/world", rhHelloWorld);
    routerRoot.addRoute("/hel", rhHel);
    routerRoot.addRoute("/items", rhItems);
    routerRoot.addRoute("/items/", rhItems2);
    routerRoot.addRoute("/items/:id", rhItemN);
    routerRoot.addRoute("/items/:id/owner", rhItemNOwner);
    routerRoot.addRoute("/items/:id/owner/pets/:petID", rhItemNOwnerPetN);
    routerRoot.addRoute("/events/:year/:month/:day/:event-name/visitors", rhVisitors);
    routerRoot.addRoute("/hello/deep/*", rhHelloDeepWildcard);

    assert(routerRoot.match("/hello/world").requestHandler == rhHelloWorld);
    assert(routerRoot.match("/hello/world").requestHandler != rhHello);
    assert(routerRoot.match("/hello").requestHandler == rhHello);
    assert(routerRoot.match("/heyo").requestHandler is null);
    assert(routerRoot.match("/hel").requestHandler == rhHel);

    assert(routerRoot.match("/items").requestHandler == rhItems);
    assert(routerRoot.match("/items/").requestHandler == rhItems2);
    assert(routerRoot.match("/items1").requestHandler is null);

    assert(routerRoot.match("/items/0001").requestHandler == rhItemN);
    assert(routerRoot.match("/items/0002").requestHandler == rhItemN);
    assert(routerRoot.match("/items/mayonnaise").requestHandler == rhItemN);
    assert(routerRoot.match("/items/mayonnaise/instrument").requestHandler is null);
    assert(routerRoot.match("/items/mayonnaise/owner").requestHandler == rhItemNOwner);
    assert(routerRoot.match("/items/xyz/owner").requestHandler == rhItemNOwner);
    assert(routerRoot.match("/items/xyz/owner/pets").requestHandler is null);
    assert(routerRoot.match("/items/xyz/owner/pets/").requestHandler is null);
    assert(routerRoot.match("/items/xyz/owner/pets/1").requestHandler == rhItemNOwnerPetN);
    assert(
        routerRoot.match("/events/1990/01/01/foobar/visitors")
            .requestHandler == rhVisitors
    );
    assert(
        routerRoot.match("/hello/deep/").requestHandler == rhHelloDeepWildcard
    );
    assert(
        routerRoot.match("/hello/deep/oachkatzlschwoaf").requestHandler == rhHelloDeepWildcard
    );
    assert(
        routerRoot.match("/hello/deep/oachkatzl/schwoaf").requestHandler == rhHelloDeepWildcard
    );

    assert(routerRoot.match("/").requestHandler == rhRoot);
    assert(routerRoot.match("oachkatzlschwoaf").requestHandler is null);

    assert(routerRoot.match("/items/0001").meta.placeholders
            == [KeyValuePair("id", "0001")]
    );
    assert(routerRoot.match("/items/0002").meta.placeholders
            == [KeyValuePair("id", "0002")]
    );
    assert(routerRoot.match("/items/thingy/owner/pets/1")
            .meta.placeholders == [
                KeyValuePair("id", "thingy"),
                KeyValuePair("petID", "1"),
            ]
    );
    assert(
        routerRoot.match("/events/2022/12/31/New%20Year%E2%80%99s%20Eve/visitors")
            .meta.placeholders == [
                KeyValuePair("year", "2022"),
                KeyValuePair("month", "12"),
                KeyValuePair("day", "31"),
                KeyValuePair("event-name", "New%20Year%E2%80%99s%20Eve"),
            ]
    );
    assert(
        routerRoot.match("/hello/deep/oachkatzlschwoaf")
            .meta.placeholders == [KeyValuePair("*", "oachkatzlschwoaf"),]
    );
    assert(
        routerRoot.match("/hello/deep/oachkatzl/schwoaf")
            .meta.placeholders == [KeyValuePair("*", "oachkatzl/schwoaf"),]
    );
}
