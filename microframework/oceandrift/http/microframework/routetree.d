module oceandrift.http.microframework.routetree;

import std.string : indexOf;
import oceandrift.http.message : hstring;
import oceandrift.http.server : RequestHandler;

@safe:

struct RouteTreeLink
{
    string component = null;
    RouteTreeNode* node;
}

struct RouteTreeNode
{
    RequestHandler requestHandler = null;

    RouteTreeLink[] branches;
    RouteTreeLink wildcard;
}

void addRoute(RouteTreeNode* root, string url, RequestHandler requestHandler)
in (url[0] == '/')
{
    return addRouteTreeNode(root, url[1 .. $], requestHandler);
}

private void addRouteTreeNode(RouteTreeNode* tree, string url, RequestHandler requestHandler)
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

        // exists (no insert)

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

        // dfmt off
        assert(
            (component == tree.wildcard.component)
            || (component == "")
            || (tree.wildcard.component == "")
            ,
            "Ambiguously named route placeholder: `"
                ~ component
                ~ "` (already knowns as: `" ~ tree.wildcard.component ~ "`)"
        );
        // dfmt on

        tree.wildcard.component = component;
        return addRouteTreeNode(tree.wildcard.node, url, requestHandler);
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
    RequestHandler rh0 = delegate(Request, Response r) { return r; };
    RequestHandler rh1 = delegate(Request, Response r) { return r.withStatus(201); };
    RequestHandler rh2 = delegate(Request, Response r) { return r.withStatus(202); };
    RequestHandler rh3 = delegate(Request, Response r) { return r.withStatus(203); };
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
}

@system unittest
{
    import std.exception : assertThrown;
    import oceandrift.http.message;

    RequestHandler rh0 = delegate(Request, Response r) { return r; };
    auto routerRoot = new RouteTreeNode();

    assertThrown!Error(routerRoot.addRoute(":id/", rh0));

    routerRoot.addRoute("/:foo", rh0);
    assertThrown!Error(routerRoot.addRoute("/:bar", rh0));

    routerRoot.addRoute("/a/:foo/x", rh0);
    assertThrown!Error(routerRoot.addRoute("/a/:bar/y", rh0));

    routerRoot.addRoute("/2000", rh0);
    assertThrown!Error(routerRoot.addRoute("/2000", rh0));
}

RequestHandler match(RouteTreeNode* root, hstring url)
{
    if (url[0] != '/')
        return null;

    return matchRoute(root, url[1 .. $]);
}

private RequestHandler matchRoute(RouteTreeNode* tree, hstring url)
{
    if (url.length == 0)
        return tree.requestHandler;

    foreach (branch; tree.branches)
    {
        if (branch.component.length > url.length) // branch can’t match
            continue;

        if (branch.component != url[0 .. branch.component.length]) // mismatch
            continue;

        return matchRoute(branch.node, url[branch.component.length .. $]);
    }

    if (tree.wildcard.node !is null)
    {
        immutable endOfWildcard = url.indexOf('/');
        if (endOfWildcard < 0)
            return matchRoute(tree.wildcard.node, "");

        return matchRoute(tree.wildcard.node, url[endOfWildcard .. $]);
    }

    return null;
}

unittest
{
    import oceandrift.http.message;

    // dfmt off
    RequestHandler rhRoot = delegate(Request, Response r) { return r; };
    RequestHandler rhHello = delegate(Request, Response r) { return r; };
    RequestHandler rhHelloWorld = delegate(Request, Response r) { return r; };
    RequestHandler rhHel = delegate(Request, Response r) { return r; };
    RequestHandler rhItems = delegate(Request, Response r) { return r; };
    RequestHandler rhItems2 = delegate(Request, Response r) { return r; };
    RequestHandler rhItemN = delegate(Request, Response r) { return r; };
    RequestHandler rhItemNOwner = delegate(Request, Response r) { return r; };
    // dfmt on

    auto routerRoot = new RouteTreeNode(rhRoot);

    routerRoot.addRoute("/hello", rhHello);
    routerRoot.addRoute("/hello/world", rhHelloWorld);
    routerRoot.addRoute("/hel", rhHel);
    routerRoot.addRoute("/items", rhItems);
    routerRoot.addRoute("/items/", rhItems2);
    routerRoot.addRoute("/items/:id", rhItemN);
    routerRoot.addRoute("/items/:id/owner", rhItemNOwner);

    assert(routerRoot.match("/hello/world") == rhHelloWorld);
    assert(routerRoot.match("/hello/world") != rhHello);
    assert(routerRoot.match("/hello") == rhHello);
    assert(routerRoot.match("/heyo") is null);
    assert(routerRoot.match("/hel") == rhHel);

    assert(routerRoot.match("/items") == rhItems);
    assert(routerRoot.match("/items/") == rhItems2);
    assert(routerRoot.match("/items1") is null);

    assert(routerRoot.match("/items/0001") == rhItemN);
    assert(routerRoot.match("/items/0002") == rhItemN);
    assert(routerRoot.match("/items/mayonnaise") == rhItemN);
    assert(routerRoot.match("/items/mayonnaise/instrument") is null);
    assert(routerRoot.match("/items/mayonnaise/owner") == rhItemNOwner);
    assert(routerRoot.match("/items/xyz/owner") == rhItemNOwner);

    assert(routerRoot.match("/") == rhRoot);
}
