/++
    Request URI handling.

    Intended for $(I Request Targets) in origin-form (see RFC 7230, section 5.3.1) only.

    $(BLOCKQUOTE
        ```
        origin-form    = absolute-path [ "?" query ]
        ```
    )

    ```
    http://www.example.org/where?q=now
    --origin-form-> /where?q=now
    ```

    See_Also:
        $(LIST
            * https://www.rfc-editor.org/rfc/rfc3986#section-3
            * https://www.rfc-editor.org/rfc/rfc7230#section-5.3.1
        )
 +/
module oceandrift.http.microframework.uri;

public import oceandrift.http.message : hstring;

@safe pure:

hstring path(hstring uri) nothrow @nogc
{
    import std.string : indexOf;

    immutable posQuery = uri.indexOf('?');

    if (posQuery < 0)
        return uri;

    return uri[0 .. posQuery];
}

///
unittest
{
    assert("/oachkatzl".path == "/oachkatzl");
    assert("/oachkatzl/schwoaf".path == "/oachkatzl/schwoaf");
    assert("/oachkatzl?a=b".path == "/oachkatzl");
    assert("/oachkatzl/schwoaf?a=b".path == "/oachkatzl/schwoaf");
}

hstring query(hstring uri) nothrow @nogc
{
    import std.string : indexOf;

    immutable posQuery = uri.indexOf('?');

    if (posQuery < 0)
        return null;

    return uri[posQuery + 1 .. $];
}

///
unittest
{
    assert("/oachkatzl".query == "");
    assert("/oachkatzl/schwoaf".query == "");
    assert("/oachkatzl?a=b".query == "a=b");
    assert("/oachkatzl/schwoaf?x=y".query == "x=y");
    assert("/oachkatzl/schwoaf?x=y&z=0".query == "x=y&z=0");
    assert("/oachkatzl/schwoaf?".query == "");
}

struct QueryParameter
{
@safe pure:

    hstring key;
    hstring value;

    URLDecoder!treatPlusAsSpace valueDecoded(bool treatPlusAsSpace = true)() nothrow @nogc
    {
        import std.uri : decodeComponent;

        return URLDecoder(this.value);
    }
}

bool isHexUpper(char c) nothrow @nogc
{
    return (c >= 'A') && (c <= 'F');
}

bool isHexLower(char c) nothrow @nogc
{
    return (c >= 'a') && (c <= 'f');
}

/++
    Hex to Ubyte

    Input MUST be two byte long
 +/
bool htoi(hstring input, out ubyte result) nothrow @nogc
{
    import std.ascii : isDigit;

    debug assert(input.length == 2);

    if (input[0].isDigit)
        result = cast(ubyte)((input[0] - '0') * 16);
    else if (input[0].isHexUpper)
        result = cast(ubyte)((input[0] - 'A' + 10) * 16);
    else if (input[0].isHexLower)
        result = cast(ubyte)((input[0] - 'a' + 10) * 16);
    else
        return false;

    if (input[1].isDigit)
        result += input[1] - '0';
    else if (input[1].isHexUpper)
        result += input[1] - 'A' + 10;
    else if (input[1].isHexLower)
        result += input[1] - 'a' + 10;
    else
        return false;

    return true;
}

unittest
{
    ubyte r = 0;
    assert(htoi("20", r));
    assert(r == ' ');
    assert(htoi("FF", r));
    assert(r == 0xFF);
    assert(htoi("0A", r));
    assert(r == 0x0A);
    assert(htoi("A0", r));
    assert(r == 0xA0);
    assert(htoi("ab", r));
    assert(r == 0xAB);
    assert(htoi("AB", r));
    assert(r == 0xAB);
    assert(htoi("ba", r));
    assert(r == 0xBA);
    assert(htoi("BA", r));
    assert(r == 0xBA);
    assert(htoi("00", r));
    assert(r == 0x00);
    assert(htoi("01", r));
    assert(r == 0x01);
    assert(htoi("10", r));
    assert(r == 0x10);
    assert(htoi("c3", r));
    assert(r == 0xC3);
    assert(htoi("C3", r));
    assert(r == 0xC3);
    assert(htoi("EB", r));
    assert(r == 0xEB);

    assert(!htoi("XY", r));
    assert(!htoi("2Y", r));
    assert(!htoi("Y2", r));
}

struct URLDecoder(bool treatPlusAsSpace = true)
{
@safe pure:

    private
    {
        hstring _input;
        size_t _n = 0;

        ubyte _front;
        bool _empty = false;
    }

    @disable this();
    this(hstring input) nothrow @nogc
    {
        _input = input;
        popFront();
    }

    char front() nothrow @nogc
    {
        return _front;
    }

    bool empty() nothrow @nogc
    {
        return _empty;
    }

    void popFront() nothrow @nogc
    {
        if (_n == _input.length)
        {
            _empty = true;
            return;
        }

        static if (treatPlusAsSpace)
        {
            if (_input[_n] == '+')
            {
                _front = ' ';
                ++_n;
                return;
            }
        }

        if (_input[_n] == '%')
        {
            immutable bool twoMoreLeft = ((_input.length - _n) > 2);
            if (twoMoreLeft)
            {
                immutable hexDecodable = htoi(_input[(_n + 1) .. (_n + 3)], _front);
                if (hexDecodable)
                {
                    _n += 3;
                    return;
                }
            }
        }

        _front = _input[_n];
        ++_n;
    }

    hstring toHString()
    {
        import std.range : array;

        return array(this);
    }
}

URLDecoder!treatPlusAsSpace urlDecode(bool treatPlusAsSpace = true)(hstring input)
{
    return URLDecoder!treatPlusAsSpace(input);
}

///
unittest
{
    import std.algorithm : equal;

    assert(urlDecode("asdf%20gh").equal("asdf gh"));
    assert(urlDecode("asdf%20gh").toHString == "asdf gh");

    assert(urlDecode("asdf%20%20gh").equal("asdf  gh"));
    assert(urlDecode("asdf%C3%BC").equal("asdfü"));
    assert(urlDecode("asdf%C3%84").equal("asdfÄ"));

    assert(urlDecode("a%2").equal("a%2")); // garbage remains garbage
    assert(urlDecode("a%2y").equal("a%2y")); // ditto
    assert(urlDecode("a%2yea").equal("a%2yea")); // ditto

    assert(urlDecode("asdf+gh").equal("asdf gh")); // '+' is treated as space by default
    assert(urlDecode("a+b").equal(urlDecode("a%20b")));
    assert(urlDecode("a%20+b").equal(urlDecode("a  b")));

    assert(urlDecode("_%C3%A4_").equal("_ä_"));
    assert(urlDecode("%C3%BC_%C3%B6").equal("ü_ö"));
    assert(urlDecode("%E2%82%AC").equal("€"));

    assert(!urlDecode!false("asdf+gh").equal("asdf gh")); // don’t treat '+' as space
    assert(urlDecode!false("asdf+gh").equal("asdf+gh")); // don’t treat '+' as space

    enum atCTFE = urlDecode("%40CTFE").toHString; // @ compile-time
    static assert(atCTFE == "@CTFE");
}

private bool shouldBeEncoded(const char c) nothrow @nogc
{
    import std.ascii : isAlphaNum;

    // dfmt off
    return !(
        c.isAlphaNum
        || c == '-'
        || c == '_'
        || c == '.'
        || c == '~'
    );
    // dfmt on
}

private ubyte toHexDigit(ubyte decimal) nothrow @nogc
{
    // Special Thanks to Steven “Schveiguy” Schveighoffer
    return "0123456789ABCDEF"[decimal];
}

unittest
{
    assert((0).toHexDigit == '0');
    assert((1).toHexDigit == '1');
    assert((2).toHexDigit == '2');
    assert((3).toHexDigit == '3');
    assert((4).toHexDigit == '4');
    assert((5).toHexDigit == '5');
    assert((6).toHexDigit == '6');
    assert((7).toHexDigit == '7');
    assert((8).toHexDigit == '8');
    assert((9).toHexDigit == '9');
    assert((10).toHexDigit == 'A');
    assert((11).toHexDigit == 'B');
    assert((12).toHexDigit == 'C');
    assert((13).toHexDigit == 'D');
    assert((14).toHexDigit == 'E');
    assert((15).toHexDigit == 'F');
}

private ubyte[2] urlEncodeChar(const char c) nothrow @nogc
{
    return [
        (ubyte(c) / 16).toHexDigit,
        (ubyte(c) % 16).toHexDigit,
    ];
}

unittest
{
    assert(urlEncodeChar(' ') == "20");
    assert(urlEncodeChar('!') == "21");
    assert(urlEncodeChar('#') == "23");
    assert(urlEncodeChar('$') == "24");
    assert(urlEncodeChar('&') == "26");
    assert(urlEncodeChar('\'') == "27");
    assert(urlEncodeChar('(') == "28");
    assert(urlEncodeChar(')') == "29");
    assert(urlEncodeChar('*') == "2A");
    assert(urlEncodeChar('+') == "2B");
    assert(urlEncodeChar(',') == "2C");
    assert(urlEncodeChar('/') == "2F");
    assert(urlEncodeChar(':') == "3A");
    assert(urlEncodeChar(';') == "3B");
    assert(urlEncodeChar('=') == "3D");
    assert(urlEncodeChar('?') == "3F");
    assert(urlEncodeChar('@') == "40");
    assert(urlEncodeChar('[') == "5B");
    assert(urlEncodeChar(']') == "5D");
}

struct URLEncoder
{
@safe pure:

    private
    {
        hstring _input;
        size_t _n = 0;

        ubyte _front;
        bool _empty = false;

        ubyte[2] _buffer = ['\xFF', '\xFF'];
        size_t _bufferLeft = 0;
    }

    @disable this();
    this(hstring input) nothrow @nogc
    {
        _input = input;
        popFront();
    }

    char front() nothrow @nogc
    {
        return _front;
    }

    bool empty() nothrow @nogc
    {
        return _empty;
    }

    void popFront() nothrow @nogc
    {
        if (_bufferLeft > 0)
        {
            enum bLength = _buffer.length;
            _front = _buffer[bLength - _bufferLeft];
            --_bufferLeft;
            return;
        }

        if (_n == _input.length)
        {
            _empty = true;
            return;
        }

        if (_input[_n].shouldBeEncoded)
        {
            _buffer[0 .. 2] = urlEncodeChar(_input[_n]);
            _bufferLeft = 2;

            _front = '%';
            ++_n;

            return;
        }

        _front = _input[_n];
        ++_n;
    }

    hstring toHString()
    {
        import std.range : array;

        return array(this);
    }
}

URLEncoder urlEncode(const hstring input) nothrow @nogc
{
    return URLEncoder(input);
}

unittest
{
    import std.algorithm : equal;

    assert(urlEncode("asdf gh").equal("asdf%20gh"));
    assert(urlEncode("asdf gh").toHString == "asdf%20gh");

    assert(urlEncode("asdf  gh").equal("asdf%20%20gh"));
    assert(urlEncode("asdf_").equal("asdf_"));
    assert(urlEncode("asdf").equal("asdf"));
    assert(urlEncode(".").equal("."));

    assert(urlEncode("_ä_").equal("_%C3%A4_"));
    assert(urlEncode("ü_ö").equal("%C3%BC_%C3%B6"));
    assert(urlEncode("€").equal("%E2%82%AC"));

    assert(urlEncode("\xFF").equal("%FF"));
    assert(urlEncode("\r\n").equal("%0D%0A"));

    enum atCTFE = urlEncode("@CTFE").toHString;
    static assert(atCTFE == "%40CTFE");
}
