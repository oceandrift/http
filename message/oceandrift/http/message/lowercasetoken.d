module oceandrift.http.message.lowercasetoken;

import oceandrift.http.message.htype;

@safe pure:

/++
    Lower-case HTTP token (tchar string)

    See_Also:
        https://www.rfc-editor.org/rfc/rfc9110#name-tokens
 +/
struct LowerCaseToken
{
@safe pure:

    static class LCTException : Exception
    {
    @nogc @safe pure nothrow:
        this(string msg, string file = __FILE__, size_t line = __LINE__)
        {
            super(msg, file, line);
        }
    }

    private
    {
        const(char)[] _data;
    }

    @disable this();

    private this(const(char)[] data) nothrow @nogc
    {
        _data = data;
    }

    hstring data() const nothrow @nogc
    {
        return _data;
    }

static:
    ///
    LowerCaseToken makeValidated(hstring input)
    {
        import std.ascii : isUpper;
        import std.format;

        foreach (size_t i, const char c; input)
            if (!c.isTChar || c.isUpper)
                throw new LCTException(format!"Invalid tchar(x%X) @%u"(c, i));

        return LowerCaseToken(input);
    }

    ///
    LowerCaseToken makeConverted(hstring input)
    {
        import std.ascii : toLower;
        import std.format;

        auto data = new char[](input.length);

        foreach (size_t i, const char c; input)
            if (c.isTChar)
                data[i] = c.toLower;
            else
                throw new LCTException(format!"Invalid tchar(x%X) @%u"(c, i));

        return LowerCaseToken(data);
    }

    ///
    LowerCaseToken makeSanitized(hstring input) nothrow
    {
        import std.ascii : toLower;

        auto data = new char[](input.length);

        foreach (size_t i, const char c; input)
            data[i] = (c.isTChar) ? c.toLower : '_';

        return LowerCaseToken(data);
    }

    ///
    LowerCaseToken makeAsIs(hstring input) nothrow @nogc
    in
    {
        import std.ascii : isUpper;

        foreach (size_t i, const char c; input)
            assert((c.isTChar && c.isUpper), "Invalid tchar encountered");
    }
    do
    {
        return LowerCaseToken(input);
    }
}

///
unittest
{
    import std.exception;

    assertNotThrown(LowerCaseToken.makeValidated("asdf"));
    assertThrown(LowerCaseToken.makeValidated("ASDF"));
    assertThrown(LowerCaseToken.makeValidated("{asdf}"));
    assertThrown(LowerCaseToken.makeValidated("A-a"));
    assertNotThrown(LowerCaseToken.makeValidated("as-df"));

    assert(LowerCaseToken.makeSanitized("asdf").data == "asdf");
    assert(LowerCaseToken.makeSanitized("ASDF").data == "asdf");
    assert(LowerCaseToken.makeSanitized("{asdf}").data == "_asdf_");
    assert(LowerCaseToken.makeSanitized("A-a").data == "a-a");
    assert(LowerCaseToken.makeSanitized("as-df").data == "as-df");
}

/++
    Case-insensitive ASCII-string comparision
 +/
bool equalsCaseInsensitive(hstring a, hstring b) pure nothrow
{
    import std.ascii : toLower;

    if (a.length != b.length)
        return false;

    foreach (size_t i, char c; a)
        if (c != b[i])
            if (c.toLower != b[i].toLower)
                return false;

    return true;
}

///
bool equalsCaseInsensitive(const hstring a, const LowerCaseToken b) pure nothrow @nogc
{
    import std.ascii : toLower;

    if (a.length != b.data.length)
        return false;

    foreach (size_t i, const char c; b.data)
        if (c != a[i])
            if (c != a[i].toLower)
                return false;

    return true;
}

///
bool equalsCaseInsensitive(const const(ubyte)[] a, const LowerCaseToken b) pure nothrow @nogc
{
    return equalsCaseInsensitive(cast(hstring) a, b);
}

bool isTChar(const char c) pure nothrow @nogc
{
    import std.ascii : isGraphical;

    if (!c.isGraphical)
        return false;

    // Delimiters are chosen from the set of US-ASCII visual characters not allowed in a token (DQUOTE and "(),/:;<=>?@[\]{}").

    // dfmt off
        if (
                (c == 34)               // '"'
            ||  (c == 40)               // '('
            ||  (c == 41)               // ')'
            ||  (c == 44)               // ','
            ||  (c == 47)               // '/'
            || ((c >= 58) && (c <= 64)) // 58 == ':', 59 == ';', 60 == '<', 61 == '=', 62 == '>', 63 == '?', 64 == '@'
            || ((c >= 91) && (c <= 93)) // 91 == '[', 92 == '\', 93 == ']'
            ||  (c == 123)              // '{'
            ||  (c == 125)              // '}'
        ) {
            return false;
        }
        // dfmt on

    return true;
}
