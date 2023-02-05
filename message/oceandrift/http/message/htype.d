/++
    DIP1000 compatible slices
 +/
module oceandrift.http.message.htype;

@safe pure nothrow:

/++
    “HTTP message string” – short-hand for `const(char)[]``.

    $(SIDEBAR
        Not sure about the name.
        Would have prefered *cstring* (*const string* as opposed to D’s default immutable one),
        but the common association with that term would be “zero-terminated string (as made famous by C)”.
    )
 +/
public alias hstring = HSlice!char;
//alias hstring = const(char)[];

///
public alias hbuffer = HSlice!ubyte;

struct HSlice(T)
{
    private
    {
        const(T)[] _data;
        bool _immortal = false;
    }

    public @safe pure nothrow @nogc
    {
        this(const(T)[] data)
        {
            _data = data;
        }

        this(T2)(HSlice!T2 ha2)
        {
            _data = cast(const(T)[]) ha2._data;
            _immortal = ha2._immortal;
        }

        private this(const(T)[] data, bool immortal)
        {
            _data = data;
            _immortal = immortal;
        }
    }

    public @safe pure nothrow @nogc
    {
        bool immortal() inout
        {
            return _immortal;
        }

        const(T)[] data() inout
        {
            return _data;
        }

        static if (is(T == char))
        {
            const(T)[] toString() inout
            {
                return _data;
            }
        }

        void drop()
        {
            _data = [];
        }

    }

    public @safe pure nothrow @nogc
    {
        /*ptrdiff_t indexOf(const(T) needle) inout
        {
            foreach (idx, c; _data)
                if (c == needle)
                    return idx;

            return -1;
        }

        ptrdiff_t indexOf(const(T)[] needle) inout
        {
            return indexOfImpl(_data, needle);
        }

        ptrdiff_t indexOf(const(T)[] needle, in size_t offset)
        {
            return indexOfImpl(_data, needle);
        }*/

        bool startsWith(const(T)[] needle)
        {
            return (_data[0 .. needle.length] == needle[0 .. $]);
        }
    }

    public @safe pure
    {
        Target to(Target)()
        {
            import std.conv : to;

            return this._data.to!Target();
        }

        Target opCast(Target)() const
        {
            import std.traits : ReturnType;

            alias E = ReturnType!(Target.init.opIndex);
            return HSlice!E(cast(const(E)[]) _data, _immortal);
        }
    }

    public @safe pure nothrow @nogc
    {
        size_t length() inout
        {
            return _data.length;
        }

        HSlice!T opSlice(size_t start, size_t end) inout
        {
            return HSlice!T(_data[start .. end], _immortal);
        }

        T opIndex(size_t index) inout
        {
            return _data[index];
        }

        size_t opDollar() inout
        {
            return this.length;
        }

        bool opEquals(R)(const R other) inout
        {
            return (_data == other);
        }
    }

    // opApply
    public
    {
        // dfmt off
        private enum opApplyImpl(string soup) = `
            int opApply(scope int delegate(size_t, const T) ` ~ soup ~ ` dg) const ` ~ soup ~ `
            {
                int result = 0;

                foreach (idx, c; _data)
                {
                    result = dg(idx, c);
                    if (result)
                        break;
                }

                return result;
            }
            int opApply(scope int delegate(size_t, T)` ~ soup ~ ` dg) const `~ soup ~ `
            {
                int result = 0;

                foreach (idx, c; _data)
                {
                    result = dg(idx, c);
                    if (result)
                        break;
                }

                return result;
            }
            int opApply(scope int delegate(const T) ` ~ soup ~ ` dg) const ` ~ soup ~ `
            {
                int result = 0;

                foreach (idx, c; _data)
                {
                    result = dg(c);
                    if (result)
                        break;
                }

                return result;
            }
        `;
        // dfmt on

        mixin(opApplyImpl!"@safe");
        mixin(opApplyImpl!"@system");
        mixin(opApplyImpl!"@safe nothrow");
        mixin(opApplyImpl!"@system nothrow");
        mixin(opApplyImpl!"@safe pure");
        mixin(opApplyImpl!"@system pure");
        mixin(opApplyImpl!"@safe nothrow pure");
        mixin(opApplyImpl!"@system nothrow pure");
        mixin(opApplyImpl!"@safe @nogc");
        mixin(opApplyImpl!"@system @nogc");
        mixin(opApplyImpl!"@safe nothrow @nogc");
        mixin(opApplyImpl!"@system nothrow @nogc");
        mixin(opApplyImpl!"@safe pure @nogc");
        mixin(opApplyImpl!"@system pure @nogc");
        mixin(opApplyImpl!"@safe nothrow pure @nogc");
        mixin(opApplyImpl!"@system nothrow pure @nogc");
    }

    // range
    public @safe pure nothrow @nogc
    {
        bool empty() inout
        {
            return this.length == 0;
        }

        T front() inout
        {
            return _data[0];
        }

        void popFront()
        {
            _data = _data[1 .. $];
        }

        T back() inout
        {
            return _data[$ - 1];
        }

        void popBack()
        {
            _data = _data[0 .. ($ - 1)];
        }

        typeof(this) save()
        {
            return this;
        }
    }
}

private
{
    import std.range;

    static assert(isInputRange!(HSlice!ubyte));
    static assert(isForwardRange!(HSlice!ubyte));
    static assert(isBidirectionalRange!(HSlice!ubyte));
    static assert(isRandomAccessRange!(HSlice!ubyte));
}

HSlice!T imdup(T)(const(T)[] data)
{
    return HSlice!T(data.idup, true);
}

HSlice!T assumeImmortal(T)(const(T)[] data) @system @nogc
{
    return HSlice!T(data, true);
}

private ptrdiff_t indexOfImpl(T)(const(T)[] haystack, const(T)[] needle)
{
    if (needle.length == 0)
        return (haystack.length > 0) ? 0 : -1;

    ptrdiff_t idx = 0;
    while (haystack.length < needle.length)
    {
        if (haystack[0] == needle[0])
        {
            immutable bool found = indexOfImplScan(haystack, needle);
            if (found)
                return true;
        }

        haystack = haystack[1 .. $];
        ++idx;
    }

    return -1;
}

private bool indexOfImplScan(T)(const(T)[] haystackLeft, const(T)[] needle)
{
    debug assert(haystackLeft.length >= needle.length);

    foreach (idx, c; needle)
        if (c != haystackLeft[0])
            return false;

    return true;
}
