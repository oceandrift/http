module oceandrift.http.microframework.html;

import std.range : ElementType, isInputRange;
import oceandrift.http.message : assumeImmortal, hstring, imdup;

@safe pure:

private
{
    struct Escape
    {
        char specialChar;
        hstring escapeSequence;
    }

    Escape[] getEscapeMap(bool escapeQuotes) nothrow
    {
        Escape[] m = [
            Escape('&', "&amp;".imdup),
            Escape('<', "&lt;".imdup),
            Escape('>', "&gt;".imdup),
        ];

        if (escapeQuotes)
        {
            m ~= Escape('"', "&quot;".imdup);
            m ~= Escape('\'', "&#39;".imdup);
        }

        return m;
    }
}

enum isHTMLEscapable(T) = (is(T == const(char)[]) || (isInputRange!T && is(ElementType!T == char)));

/++
    HTML escaping implementation
 +/
struct HTMLEscaper(bool escapeQuotes = true, TInput) if (isHTMLEscapable!TInput)
{
@safe pure nothrow:

    private
    {
        static immutable _escapeMap = getEscapeMap(escapeQuotes);

        TInput _input;

        bool _empty = true;
        char _front;

        hstring _buffer = null;
    }

    /++
        See_Also:
            [htmlEscape]
     +/
    this(TInput input) @nogc
    {
        _empty = false;
        _input = input;
        loadFront();
    }

    ///
    bool empty() @nogc
    {
        return _empty;
    }

    ///
    char front() @nogc
    {
        return _front;
    }

    ///
    void popFront() @nogc
    {
        if (_buffer.length > 0) // data in buffer?
        {
            _front = _buffer[0];
            _buffer = _buffer[1 .. $];
            return;
        }

        _input.popFront();
        this.loadFront();
    }

    private void loadFront() @nogc
    {
        if (_input.empty) // input empty?
        {
            _empty = true;
            return;
        }

        // needs escaping?
        static foreach (esc; _escapeMap)
        {
            if (_input.front == esc.specialChar)
            {
                _front = esc.escapeSequence[0]; // store first char of escape sequence in front
                _buffer = esc.escapeSequence[1 .. $]; // load rest into buffer
                return;
            }
        }

        // no escaping
        _front = _input.front;
    }

    ///
    hstring toHString()
    {
        import std.range : array;

        return (const(char)[] d) @trusted { return assumeImmortal(d); }(array(this));
    }
}

/++
    Escape input for use in HTML

    Input can be either a string or a compatible input range.

    Escaping of quotes (double quotes (`"`) and single quotes (`'`))
    can be configured by using the first template parameter.
    Use `htmlEscape!false()` to disable escaping of quotes.

    Returns:
        Input Range; call `.toHString` to convert it into an hstring
 +/
HTMLEscaper!(escapeQuotes, TInput) htmlEscape(bool escapeQuotes = true, TInput)(TInput input) nothrow @nogc
        if (isHTMLEscapable!TInput)
{
    return HTMLEscaper!(escapeQuotes, TInput)(input);
}

/// ditto
HTMLEscaper!(escapeQuotes, hstring) htmlEscape(bool escapeQuotes = true, TInput:
    string)(TInput input) nothrow @nogc
{
    return HTMLEscaper!(escapeQuotes, hstring)(hstring(input));
}

/// ditto
HTMLEscaper!(escapeQuotes, hstring) htmlEscape(bool escapeQuotes = true, TInput:
    const(char)[])(TInput input) nothrow @nogc
{
    return HTMLEscaper!(escapeQuotes, hstring)(hstring(input));
}

unittest
{
    auto escaped = htmlEscape("<html>");
    assert(!escaped.empty);
    assert(escaped.front == '&');

    escaped.popFront();
    assert(escaped.front == 'l');
    escaped.popFront();
    assert(escaped.front == 't');
    escaped.popFront();
    assert(escaped.front == ';');
    escaped.popFront();
    assert(escaped.front == 'h');
    escaped.popFront();
    assert(escaped.front == 't');
    escaped.popFront();
    assert(escaped.front == 'm');
    escaped.popFront();
    assert(escaped.front == 'l');
    escaped.popFront();
    assert(escaped.front == '&');
    escaped.popFront();
    assert(escaped.front == 'g');
    escaped.popFront();
    assert(escaped.front == 't');
    escaped.popFront();
    assert(escaped.front == ';');

    escaped.popFront();
    assert(escaped.empty);
}

///
unittest
{
    assert(htmlEscape("<html>").toHString == "&lt;html&gt;");
    assert(htmlEscape("<<html>>").toHString == "&lt;&lt;html&gt;&gt;");

    assert(htmlEscape("Dlang & co.").toHString == "Dlang &amp; co.");

    assert(htmlEscape(`<p style="background: #FFF">`)
            .toHString == "&lt;p style=&quot;background: #FFF&quot;&gt;");

    assert(htmlEscape!false(`<p style="background: #FFF">`)
            .toHString == `&lt;p style="background: #FFF"&gt;`);

    assert(htmlEscape(`<p style='background: #FFF'>`)
            .toHString == `&lt;p style=&#39;background: #FFF&#39;&gt;`);

    hstring txt = `<better escape="me" />`;
    assert(htmlEscape(txt).toHString == "&lt;better escape=&quot;me&quot; /&gt;");

}

///
unittest
{
    // Chain url-decoding with html-escaping:
    import oceandrift.http.microframework.uri;

    // <script>alert('xss');</script>
    const decodedAndEscaped = urlDecode("%3Cscript%3Ealert%28%27xss%27%29%3B%3C%2Fscript%3E")
        .htmlEscape()
        .toHString;

    assert(decodedAndEscaped == "&lt;script&gt;alert(&#39;xss&#39;);&lt;/script&gt;");
}
