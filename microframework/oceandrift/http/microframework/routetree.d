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
 +/
module oceandrift.http.microframework.routetree;

import std.string : indexOf;
import oceandrift.http.message : hstring, imdup, Request, Response;
import oceandrift.http.microframework.kvp;

@safe:

alias RoutedRequestHandler = Response delegate(
    Request request,
    Response response,
    RouteMatchMeta meta,
) @safe;

///
struct RouteTreeLink
{
    hstring component = hstring(null);
    RouteTreeNode* node;
}

///
struct RouteTreeNode
{
    RoutedRequestHandler requestHandler = null;

    RouteTreeLink[] branches;
    RouteTreeLink wildcard;
}

///
void addRoute(RouteTreeNode* root, string url, RoutedRequestHandler requestHandler)
in (root !is null)
in (url[0] == '/')
{
    return addRouteTreeNode(root, url[1 .. $].imdup, requestHandler);
}

private void addRouteTreeNode(RouteTreeNode* tree, hstring url, RoutedRequestHandler requestHandler)
{
    if (url.length == 0)
    {
        assert(tree.requestHandler is null, "Duplicate route");

        tree.requestHandler = requestHandler;
        return;
    }

    // wildcard
    if (url[0] == ':')
    {
        url = url[1 .. $];

        immutable ptrdiff_t endOfWildcard = url.indexOf('/');

        if (tree.wildcard.node is null) // insert
        {
            tree.wildcard.node = new RouteTreeNode();

            if (endOfWildcard < 0) // end of url reached
            {
                tree.wildcard.component = url[0 .. $];
                tree.wildcard.node.requestHandler = requestHandler;
                return;
            }

            tree.wildcard.component = url[0 .. endOfWildcard];
            return addRouteTreeNode(tree.wildcard.node, url[endOfWildcard .. $], requestHandler);
        }

        // exists (no direct insert)

        hstring component;

        if (endOfWildcard < 0)
        {
            component = url[0 .. $];
            url = "".imdup;
        }
        else
        {
            component = url[0 .. endOfWildcard];
            url = url[endOfWildcard .. $];
        }

        // dfmt off
        assert(
            (component == tree.wildcard.component)
            || (component == "")
            || (tree.wildcard.component == "")
            ,
            "Ambiguously named route placeholder: `"
                ~ component.data
                ~ "` (already knowns as: `" ~ tree.wildcard.component.data ~ "`)"
        );
        // dfmt on

        tree.wildcard.component = component;
        return addRouteTreeNode(tree.wildcard.node, url, requestHandler);
    }

    foreach (ref branch; tree.branches)
    {
        if (branch.component[0] != url[0])
            continue;

        hstring shorter, longer;
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
                auto replacementNode = new RouteTreeNode(requestHandler, [
                        RouteTreeLink(branch.component[shorter.length .. $], branch.node) // link to existing node
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

        auto replacementNode = new RouteTreeNode(null, [
                RouteTreeLink(branch.component[idxSplit .. $], branch.node) // link to existing node
            ]
        );

        addRouteTreeNode(replacementNode, url[idxSplit .. $], requestHandler);
        branch.component = url[0 .. idxSplit];
        branch.node = replacementNode;

        return;
    }

    // insert

    immutable nextWildcard = url.indexOf(':');
    if (nextWildcard < 0) // no wildcard left, simple insert
    {
        tree.branches ~= RouteTreeLink(url, new RouteTreeNode(requestHandler));
        return;
    }

    auto beforeWildcard = new RouteTreeNode();
    addRouteTreeNode(beforeWildcard, url[nextWildcard .. $], requestHandler);
    tree.branches ~= RouteTreeLink(url[0 .. nextWildcard], beforeWildcard);
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

    auto routerRoot = new RouteTreeNode();

    routerRoot.addRoute("/hello", rh0);
    assert(routerRoot.requestHandler is null);
    assert(routerRoot.wildcard.node is null);
    assert(routerRoot.branches.length == 1);
    assert(routerRoot.branches[0].component == "hello");
    assert(routerRoot.branches[0].node.requestHandler == rh0);
    assert(routerRoot.branches[0].node.branches.length == 0);
    assert(routerRoot.branches[0].node.wildcard.node is null);

    routerRoot.addRoute("/world", rh1);
    assert(routerRoot.requestHandler is null);
    assert(routerRoot.wildcard.node is null);
    assert(routerRoot.branches.length == 2);
    assert(routerRoot.branches[0].component == "hello");
    assert(routerRoot.branches[0].node.requestHandler == rh0);
    assert(routerRoot.branches[0].node.branches.length == 0);
    assert(routerRoot.branches[0].node.wildcard.node is null);
    assert(routerRoot.branches[1].component == "world");
    assert(routerRoot.branches[1].node.requestHandler == rh1);
    assert(routerRoot.branches[1].node.branches.length == 0);
    assert(routerRoot.branches[1].node.wildcard.node is null);

    routerRoot.addRoute("/hello-world", rh2);
    assert(routerRoot.requestHandler is null);
    assert(routerRoot.wildcard.node is null);
    assert(routerRoot.branches.length == 2);
    assert(routerRoot.branches[0].component == "hello");
    assert(routerRoot.branches[0].node.requestHandler == rh0);
    assert(routerRoot.branches[0].node.branches.length == 1);
    assert(routerRoot.branches[0].node.branches[0].component == "-world");
    assert(routerRoot.branches[0].node.branches[0].node.requestHandler == rh2);
    assert(routerRoot.branches[0].node.branches[0].node.branches.length == 0);
    assert(routerRoot.branches[0].node.branches[0].node.wildcard.node is null);

    routerRoot.addRoute("/hello_there", rh1);
    assert(routerRoot.requestHandler is null);
    assert(routerRoot.wildcard.node is null);
    assert(routerRoot.branches.length == 2);
    assert(routerRoot.branches[0].component == "hello");
    assert(routerRoot.branches[0].node.requestHandler == rh0);
    assert(routerRoot.branches[0].node.branches.length == 2);
    assert(routerRoot.branches[0].node.branches[0].component == "-world");
    assert(routerRoot.branches[0].node.branches[0].node.requestHandler == rh2);
    assert(routerRoot.branches[0].node.branches[0].node.branches.length == 0);
    assert(routerRoot.branches[0].node.branches[0].node.wildcard.node is null);
    assert(routerRoot.branches[0].node.branches[1].component == "_there");
    assert(routerRoot.branches[0].node.branches[1].node.requestHandler == rh1);
    assert(routerRoot.branches[0].node.branches[1].node.branches.length == 0);
    assert(routerRoot.branches[0].node.branches[1].node.wildcard.node is null);

    routerRoot.addRoute("/hello_you", rh3);
    assert(routerRoot.branches[0].component == "hello");
    assert(routerRoot.branches[0].node.requestHandler == rh0);
    assert(routerRoot.branches[0].node.branches.length == 2);
    assert(routerRoot.branches[0].node.branches[1].component == "_");
    assert(routerRoot.branches[0].node.branches[1].node.requestHandler is null);
    assert(routerRoot.branches[0].node.branches[1].node.wildcard.node is null);
    assert(routerRoot.branches[0].node.branches[1].node.branches.length == 2);
    assert(routerRoot.branches[0].node.branches[1].node.branches[0].component == "there");
    assert(routerRoot.branches[0].node.branches[1].node.branches[0].node.requestHandler == rh1);
    assert(routerRoot.branches[0].node.branches[1].node.branches[1].component == "you");
    assert(routerRoot.branches[0].node.branches[1].node.branches[1].node.requestHandler == rh3);

    routerRoot.addRoute("/world/:no", rh3);
    assert(routerRoot.branches.length == 2);
    assert(routerRoot.branches[1].node.branches.length == 1);
    assert(routerRoot.branches[1].node.wildcard.node is null);
    assert(routerRoot.branches[1].node.branches[0].component == "/");
    assert(routerRoot.branches[1].node.branches[0].node.requestHandler is null);
    assert(routerRoot.branches[1].node.branches[0].node.branches.length == 0);
    assert(routerRoot.branches[1].node.branches[0].node.wildcard.component == "no");
    assert(routerRoot.branches[1].node.branches[0].node.wildcard.node.wildcard.node is null);
    assert(routerRoot.branches[1].node.branches[0].node.wildcard.node.branches.length == 0);
    assert(routerRoot.branches[1].node.branches[0].node.wildcard.node.requestHandler == rh3);

    routerRoot.addRoute("/world/:no/asdf", rh2);
    assert(routerRoot.branches[1].node.branches[0].node.wildcard.component == "no");
    assert(routerRoot.branches[1].node.branches[0].node.branches.length == 0);
    assert(routerRoot.branches[1].node.branches[0].node.wildcard.node.wildcard.node is null);
    assert(routerRoot.branches[1].node.branches[0].node.wildcard.node.branches.length == 1);
    assert(
        routerRoot.branches[1].node.branches[0].node.wildcard.node.branches[0].component == "/asdf"
    );
    assert(
        routerRoot.branches[1].node.branches[0].node.wildcard.node.branches[0]
            .node.requestHandler == rh2
    );

    routerRoot.addRoute("/world/:no/", rh1);
    assert(routerRoot.branches.length == 2);
    assert(routerRoot.branches[1].node.branches.length == 1);
    assert(routerRoot.branches[1].node.branches[0].node.wildcard.node.branches.length == 1);
    assert(routerRoot.branches[1].node.branches[0].node.wildcard.node.branches[0].component == "/");
    assert(
        routerRoot.branches[1].node.branches[0].node.wildcard.node.branches[0]
            .node.branches.length == 1
    );
    assert(routerRoot.branches[1].node.branches[0].node.wildcard.node
            .branches[0].node.branches[0].component == "asdf"
    );
    assert(routerRoot.branches[1].node.branches[0].node.wildcard.node
            .branches[0].node.branches[0].node.requestHandler == rh2
    );
    assert(
        routerRoot.branches[1].node.branches[0].node.wildcard.node
            .branches[0].node.requestHandler == rh1
    );
    assert(
        routerRoot.branches[1].node.branches[0].node.wildcard.node
            .branches[0].node.wildcard.node is null
    );

    routerRoot.addRoute("/foo/:var/", rh2);
    assert(routerRoot.branches[2].component == "foo/");
    assert(routerRoot.branches[2].node.requestHandler is null);
    assert(routerRoot.branches[2].node.wildcard.component == "var");
    assert(routerRoot.branches[2].node.wildcard.node !is null);
    assert(routerRoot.branches[2].node.wildcard.node.requestHandler is null);
    assert(routerRoot.branches[2].node.wildcard.node.branches.length == 1);
    assert(routerRoot.branches[2].node.wildcard.node.branches[0].component == "/");
    assert(routerRoot.branches[2].node.wildcard.node.branches[0].node.requestHandler == rh2);

    routerRoot.addRoute("/foo/:var", rh0);
    assert(routerRoot.branches[2].node.wildcard.node.branches[0].node.requestHandler == rh2);
    assert(routerRoot.branches[2].node.wildcard.node.requestHandler == rh0);

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
    assert(routerRoot.wildcard.node !is null);
    assert(routerRoot.wildcard.component == "1");
    assert(routerRoot.wildcard.node.branches[0].component == "/");
    assert(routerRoot.wildcard.node.branches[0].node.wildcard.node !is null);
    assert(routerRoot.wildcard.node.branches[0].node.wildcard.component == "2");
    assert(routerRoot.wildcard.node.branches[0].node.wildcard.node.requestHandler == rh0);
    routerRoot.addRoute("/:1/:2/gulaschsuppm", rh1);
    assert(
        routerRoot.wildcard.node.branches[0].node.wildcard.node.branches[0].component == "/gulaschsuppm"
    );
    assert(
        routerRoot.wildcard.node.branches[0].node.wildcard.node.branches[0]
            .node.requestHandler == rh1
    );
}

@system unittest
{
    import std.exception : assertThrown;
    import oceandrift.http.message;

    RoutedRequestHandler rh0 = delegate(Request, Response r, RouteMatchMeta) {
        return r;
    };
    auto routerRoot = new RouteTreeNode();

    assertThrown!Error(routerRoot.addRoute(":id/", rh0));

    routerRoot.addRoute("/:foo", rh0);
    assertThrown!Error(routerRoot.addRoute("/:bar", rh0));

    routerRoot.addRoute("/a/:foo/x", rh0);
    assertThrown!Error(routerRoot.addRoute("/a/:bar/y", rh0));

    routerRoot.addRoute("/2000", rh0);
    assertThrown!Error(routerRoot.addRoute("/2000", rh0));
}

struct RouteMatchMeta
{
    KeyValuePair[] placeholders;
}

struct RouteMatchResult
{
    RoutedRequestHandler requestHandler;
    RouteMatchMeta meta;
}

///
RouteMatchResult match(RouteTreeNode* root, hstring url)
{
    if (url[0] != '/')
        return RouteMatchResult(null);

    RouteMatchResult output;
    output.requestHandler = matchRoute(root, url[1 .. $], output.meta);
    return output;
}

/// ditto
RouteMatchResult match(RouteTreeNode* root, const(char)[] url)
{
    return match(root, hstring(url));
}

private RoutedRequestHandler matchRoute(RouteTreeNode* tree, hstring url, ref RouteMatchMeta routeMatchMeta)
{
    // direct match?
    if (url.length == 0)
        return tree.requestHandler;

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
    if (tree.wildcard.node !is null)
    {
        ptrdiff_t endOfWildcard = url.indexOf('/');

        if (endOfWildcard < 0)
            endOfWildcard = url.length;

        routeMatchMeta.placeholders ~= KeyValuePair(tree.wildcard.component, url[0 .. endOfWildcard]);
        return matchRoute(tree.wildcard.node, url[endOfWildcard .. $], routeMatchMeta);
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
    // dfmt on

    auto routerRoot = new RouteTreeNode(rhRoot);

    routerRoot.addRoute("/hello", rhHello);
    routerRoot.addRoute("/hello/world", rhHelloWorld);
    routerRoot.addRoute("/hel", rhHel);
    routerRoot.addRoute("/items", rhItems);
    routerRoot.addRoute("/items/", rhItems2);
    routerRoot.addRoute("/items/:id", rhItemN);
    routerRoot.addRoute("/items/:id/owner", rhItemNOwner);
    routerRoot.addRoute("/items/:id/owner/pets/:petID", rhItemNOwnerPetN);
    routerRoot.addRoute("/events/:year/:month/:day/:event-name/visitors", rhVisitors);

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
        routerRoot.match("/events/:year/:month/:day/:event-name/visitors")
            .requestHandler == rhVisitors);

    assert(routerRoot.match("/").requestHandler == rhRoot);
    assert(routerRoot.match("oachkatzlschwoaf").requestHandler is null);

    assert(routerRoot.match("/items/0001").meta.placeholders
            == [KeyValuePair("id", "0001")]);
    assert(routerRoot.match("/items/0002").meta.placeholders
            == [KeyValuePair("id", "0002")]);
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
}
