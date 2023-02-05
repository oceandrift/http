/++
    Universal header parser

    Designed for multipart files.

    Supported format:
    ---
    <Key>: <main-value>; <param1>; <param2>; <param3>; …
    ---
 +/
module oceandrift.http.microframework.hparser;

import oceandrift.http.message : hstring;
import oceandrift.http.microframework.kvp;
import std.string : indexOf, strip;

@safe pure nothrow @nogc:

///
struct HeaderValue
{
    ///
    hstring main;

    ///
    HeaderValueParamsParser params;
}

///
struct Header
{
    ///
    hstring name;

    ///
    HeaderValue value;
}

///
Header parseHeader(hstring raw)
{
    immutable ptrdiff_t idxSep = raw.indexOf(':');
    if (idxSep < 0)
        return Header(raw);

    return Header(
        raw[0 .. idxSep],
        parseHeaderValue(raw[(idxSep + 1) .. $]),
    );
}

/// ditto
Header parseHeader(const(char)[] raw)
{
    return parseHeader(hstring(raw));
}

///
unittest
{
    Header h = parseHeader(`Content-Disposition: form-data; name="file1"; filename="a.txt"`);
    assert(h.name == "Content-Disposition");
    assert(h.value.main == "form-data");

    HeaderValueParamsParser p = h.value.params;
    assert(!p.empty);
    assert(p.front == KeyValuePair("name", "file1"));
    p.popFront();
    assert(!p.empty);
    assert(p.front == KeyValuePair("filename", "a.txt"));
    p.popFront();
    assert(p.empty);
}

///
unittest
{
    Header h = parseHeader(`Content-Type: text/plain;charset=UTF-8`);
    assert(h.name == "Content-Type");
    assert(h.value.main == "text/plain");

    assert(!h.value.params.empty);
    assert(h.value.params.front == KeyValuePair("charset", "UTF-8"));
    h.value.params.popFront();
    assert(h.value.params.empty);
}

unittest
{
    Header h = parseHeader(`Whatever:v=v;q=1234;m2=" _";;`);
    assert(h.name == "Whatever");
    assert(h.value.main == "v=v");

    assert(!h.value.params.empty);
    assert(h.value.params.front == KeyValuePair("q", "1234"));
    h.value.params.popFront();
    assert(!h.value.params.empty);
    assert(h.value.params.front == KeyValuePair("m2", " _"));
    h.value.params.popFront();
    assert(h.value.params.empty);
}

HeaderValue parseHeaderValue(hstring raw)
{
    immutable ptrdiff_t idxSep = raw.indexOf(';');

    // no separator?
    if (idxSep < 0)
        return HeaderValue(raw.strip());

    return HeaderValue(
        raw[0 .. idxSep].strip(),
        parseHeaderValueParams(raw[(idxSep + 1) .. $]),
    );
}

HeaderValue parseHeaderValue(const(char)[] raw)
{
    return parseHeaderValue(hstring(raw));
}

unittest
{
    HeaderValue hv = parseHeaderValue("thingy; raspberry=pie");
    assert(hv.main == "thingy");
    assert(hv.params.front == KeyValuePair("raspberry", "pie"));
}

unittest
{
    HeaderValue hv = parseHeaderValue("thingy;raspberry=pie");
    assert(hv.main == "thingy");
    assert(hv.params.front == KeyValuePair("raspberry", "pie"));
}

unittest
{
    // garbage input
    HeaderValue hv = parseHeaderValue(";raspberry=pie");
    assert(hv.main == "");
    assert(hv.params.front == KeyValuePair("raspberry", "pie"));
}

unittest
{
    HeaderValue hv = parseHeaderValue(`mm; raspberry="pie"; oachkatzl="schwoaf"`);
    assert(hv.main == "mm");
    assert(hv.params.front == KeyValuePair("raspberry", "pie"));
    hv.params.popFront();
    assert(hv.params.front == KeyValuePair("oachkatzl", "schwoaf"));
    hv.params.popFront();
    assert(hv.params.empty);
}

HeaderValueParamsParser parseHeaderValueParams(hstring input)
{
    return HeaderValueParamsParser(input);
}

HeaderValueParamsParser parseHeaderValueParams(const(char)[] input)
{
    return parseHeaderValueParams(hstring(input));
}

struct HeaderValueParamsParser
{
@safe pure nothrow @nogc:

    private
    {
        bool _empty = true;
        KeyValuePair _current;
        hstring _input;
    }

    this(hstring input)
    {
        _input = input;
        _empty = false;
        popFront();
    }

    ///
    bool empty()
    {
        return _empty;
    }

    ///
    KeyValuePair front()
    {
        return _current;
    }

    ///
    void popFront()
    {
        // skip spaces
        do
        {
            // empty?
            if (_input.length == 0)
            {
                _empty = true;
                return;
            }

            // not a space AND not an empty param (quirk)?
            if ((_input[0] != ' ') && (_input[0] != ';'))
                break;

            // advance scanner
            _input = _input[1 .. $];
        }
        while (true);

        // parse next param

        // reset front
        _current = KeyValuePair();

        // find end-of-key/start-of-value
        immutable idxKeyValueSep = _input.indexOf('=');

        // no key/value separator?
        if (idxKeyValueSep < 0)
        {
            // look for a params separator indicating further params
            ptrdiff_t idxParamSep = _input.indexOf(';');

            // no further params?
            if (idxParamSep < 0)
                idxParamSep = _input.length;

            _current.key = _input;
            _input = _input[idxParamSep .. $];
            return;
        }

        // store key, then continue with parsing the corresponding value
        _current.key = _input[0 .. idxKeyValueSep];
        _input = _input[(idxKeyValueSep + 1) .. $];

        // no data (value) left?
        if (_input.length == 0)
        {
            // key is set already, keep the empty value
            return;
        }

        // value quoted?
        if (_input[0] == '"')
        {
            _input = _input[1 .. $];
            ptrdiff_t idxClosingQuote = _input.indexOf('"');
            ptrdiff_t idxAfterClosingQuoteScanTo = idxClosingQuote + 1;

            // closing quote missing?
            if (idxClosingQuote < 0)
            {
                // quirks
                idxClosingQuote = _input.length;
                idxAfterClosingQuoteScanTo = _input.length;
            }

            // store quoted value
            _current.value = _input[0 .. idxClosingQuote];
            _input = _input[idxAfterClosingQuoteScanTo .. $];
            return;
        }

        // no quote

        // scan for end of value
        ptrdiff_t idxEndOfValue = _input.indexOf(';');

        // ends at end-of-string?
        if (idxEndOfValue < 0)
            idxEndOfValue = _input.length;

        _current.value = _input[0 .. idxEndOfValue].strip();
        _input = _input[idxEndOfValue .. $];
    }
}

unittest
{
    auto hvp = parseHeaderValueParams(`raspberry=pie`);
    assert(!hvp.empty);
    assert(hvp.front == KeyValuePair("raspberry", "pie"));
    hvp.popFront();
    assert(hvp.empty);
}

unittest
{
    auto hvp = parseHeaderValueParams(`raspberry="pie"`);
    assert(!hvp.empty);
    assert(hvp.front == KeyValuePair("raspberry", "pie"));
    hvp.popFront();
    assert(hvp.empty);
}

unittest
{
    auto hvp = parseHeaderValueParams(`; raspberry=pie`);
    assert(!hvp.empty);
    assert(hvp.front == KeyValuePair("raspberry", "pie"));
    hvp.popFront();
    assert(hvp.empty);
}

unittest
{
    auto hvp = parseHeaderValueParams(`; raspberry="pie"`);
    assert(!hvp.empty);
    assert(hvp.front == KeyValuePair("raspberry", "pie"));
    hvp.popFront();
    assert(hvp.empty);
}

unittest
{
    auto hvp = parseHeaderValueParams(`; raspberry=" pie "`);
    assert(!hvp.empty);
    assert(hvp.front == KeyValuePair("raspberry", " pie "));
    hvp.popFront();
    assert(hvp.empty);
}

unittest
{
    auto hvp = parseHeaderValueParams(`; raspberry=" pie"; gugel="hupf "`);
    assert(!hvp.empty);
    assert(hvp.front == KeyValuePair("raspberry", " pie"));
    hvp.popFront();
    assert(!hvp.empty);
    assert(hvp.front == KeyValuePair("gugel", "hupf "));
    hvp.popFront();
    assert(hvp.empty);
}

unittest
{
    auto hvp = parseHeaderValueParams(`;party=fun   ;   x="y"`);
    assert(!hvp.empty);
    assert(hvp.front == KeyValuePair("party", "fun"));
    hvp.popFront();
    assert(!hvp.empty);
    assert(hvp.front == KeyValuePair("x", "y"));
    hvp.popFront();
    assert(hvp.empty);
}

unittest
{
    auto hvp = parseHeaderValueParams(`;party=fun;;x="y"`);
    assert(!hvp.empty);
    assert(hvp.front == KeyValuePair("party", "fun"));
    hvp.popFront();
    assert(!hvp.empty);
    assert(hvp.front == KeyValuePair("x", "y"));
    hvp.popFront();
    assert(hvp.empty);
}

unittest
{
    auto hvp = parseHeaderValueParams(` raspberry="pie"; oachkatzl="schwoaf"`);
    assert(!hvp.empty);
    assert(hvp.front == KeyValuePair("raspberry", "pie"));
    hvp.popFront();
    assert(!hvp.empty);
    assert(hvp.front == KeyValuePair("oachkatzl", "schwoaf"));
    hvp.popFront();
    assert(hvp.empty);
}

unittest
{
    auto hvp = parseHeaderValueParams(`raspberry="pie`);
    assert(!hvp.empty);
    assert(hvp.front == KeyValuePair("raspberry", "pie"));
    hvp.popFront();
    assert(hvp.empty);
}

unittest
{
    auto hvp = parseHeaderValueParams(`;;;`);
    assert(hvp.empty);
}

unittest
{
    // Might change in the future
    auto hvp = parseHeaderValueParams(`a=`);
    assert(!hvp.empty);
    assert(hvp.front == KeyValuePair("a", null));
}

unittest
{
    // Might change in the future
    auto hvp = parseHeaderValueParams(`a=;b`);
    assert(!hvp.empty);
    assert(hvp.front == KeyValuePair("a", null));
    hvp.popFront();
    assert(!hvp.empty);
    assert(hvp.front == KeyValuePair("b", null));
    hvp.popFront();
    assert(hvp.empty);
}

unittest
{
    // Might change in the future
    auto hvp = parseHeaderValueParams(`=a`);
    assert(!hvp.empty);
    assert(hvp.front == KeyValuePair(null, "a"));
}

unittest
{
    // Might change in the future

    // This case can be unexpected
    // but is probably logical to keep this way.
    // When key or value is exclusively empty, the param is not skipped either.
    auto hvp = parseHeaderValueParams(`=`);
    assert(!hvp.empty);
    assert(hvp.front == KeyValuePair(null, null));
}

unittest
{
    HeaderValueParamsParser hvp;
    assert(hvp.empty);
}
