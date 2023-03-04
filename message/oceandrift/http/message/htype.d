module oceandrift.http.message.htype;

public @safe pure nothrow @nogc:

/++
    “HTTP message string” – short-hand for `const(char)[]``.

    $(SIDEBAR
        Not sure about the name.
        Would have prefered *cstring* (*const string* as opposed to D’s default immutable one),
        but the common association with that term would be “zero-terminated string (as made famous by C)”.
    )
 +/
alias hstring = const(char)[];

///
alias hbuffer = const(ubyte)[];

/// Emulate input range
char front(const hstring s)
{
    return s[0];
}

/// ditto
bool empty(const hstring s)
{
    return (s.length == 0);
}

/// ditto
void popFront(ref hstring s)
{
    s = s[1 .. $];
}

/// Emulate input range
char front(const hbuffer s)
{
    return s[0];
}

/// ditto
bool empty(const hbuffer s)
{
    return (s.length == 0);
}

/// ditto
void popFront(ref hbuffer s)
{
    s = s[1 .. $];
}
