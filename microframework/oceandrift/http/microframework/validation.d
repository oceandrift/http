/++
    Input validation
 +/
module oceandrift.http.microframework.validation;

import oceandrift.http.message : hstring;
import oceandrift.http.microframework.kvp;
import std.range : isInputRange;
import std.traits : FieldNameTuple, Fields, hasUDA;

public import oceandrift.validation.validate;

@safe pure nothrow:

/++
    is-set constraint @UDA
 +/
struct isSet
{
}

///
ValidationResult!Data validateFormData(Data, bool allowExtraFields = true, bool bailOut = false, InputRange)(
    InputRange input)
        if ((isRangeOfKeyValuePairs!InputRange || is(InputRange == KeyValuePair[]))
        && (is(Data == struct) || is(Data == class)))
{
    // create an instance of Data
    static if (is(Data == struct))
        auto data = Data();
    else static if (is(Data == class))
        auto data = new Data();
    else
        static assert(false, "BUG");

    bool ok = true;
    ValidationError[ValidationResult!(Data).init._errors.length] errors;

    // setup a struct to track @isSet
    auto isSetCollection = IsSetCollection!Data();

    // transfer data from input key/value pairs to the Data data-structure
    foreach (size_t idx, KeyValuePair kvp; input)
    {
        immutable valid = validateImplFieldNameSwitch!allowExtraFields(
            kvp,
            data,
            isSetCollection,
            errors[idx],
        );

        if (!valid)
        {
            static if (bailOut)
                return ValidationResult!Data(false, Data.init, errors);

            ok = false;
        }
    }

    // validate @isSet constraint
    static foreach (idx, field; IsSetCollection!(Data).tupleof)
    {
        {
            enum fieldName = __traits(identifier, field);
            mixin(`immutable bool isSetOk = isSetCollection.` ~ fieldName ~ `;`);
            if (!isSetOk)
            {
                if (errors[idx].message is null)
                    errors[idx] = ValidationError(fieldName, "must be set");

                static if (bailOut)
                    return ValidationResult!Data(false, Data.init, errors);

                ok = false;
            }
        }
    }

    // validate transformed data
    ValidationResult!Data rTransformedData = validate!bailOut(data);

    ok &= rTransformedData.ok;

    if (!ok)
    {
        // merge error messages
        foreach (idx, error; rTransformedData._errors)
            if (errors[idx].message is null)
                errors[idx] = error;

        return ValidationResult!Data(false, Data.init, errors);
    }

    return rTransformedData;
}

///
unittest
{
    struct Data
    {
        import oceandrift.validation.constraints;

        @notEmpty
        string name;

        @positive
        int age;
    }

    ValidationResult!Data r = validateFormData!Data([
        KeyValuePair("name", "Tom"),
        KeyValuePair("age", "20"),
    ]);

    assert(r.ok);
    assert(r.data.name == "Tom");
    assert(r.data.age == 20);
}

///
unittest
{
    struct Data
    {
        import oceandrift.validation.constraints;

        @notEmpty
        string name;

        @positive
        int age;
    }

    ValidationResult!Data r = validateFormData!Data([
        KeyValuePair("name", "Tom"),
        KeyValuePair("age", "-1"),
    ]);

    assert(!r.ok);
}

///
unittest
{
    struct Data
    {
        import oceandrift.validation.constraints;

        @isSet
        string name;

        @isSet @positive
        int age;
    }

    ValidationResult!Data r = validateFormData!Data([
        KeyValuePair("name", null),
        KeyValuePair("age", "30"),
    ]);
    assert(r.ok);

    ValidationResult!Data r2 = validateFormData!Data([
        // no "name" set
        KeyValuePair("age", "30"),
    ]);
    assert(!r2.ok);
}

// stores a bool for each field of `T``
private struct IsSetCollection(T)
{
    static foreach (field; T.tupleof)
        static if (hasUDA!(field, isSet))
            mixin(`bool ` ~ __traits(identifier, field) ~ ` = false;`);
}

//
private bool validateImplFieldNameSwitch(bool allowExtraFields, Data)(
    KeyValuePair kvp,
    ref Data data,
    ref IsSetCollection!Data isSetCollection,
    out ValidationError error,
)
{
    pragma(inline, true);

    switch (kvp.key)
    {
        static foreach (fieldName; FieldNameTuple!Data)
        {
            {
                mixin(`alias FieldType = typeof(Data().` ~ fieldName ~ `);`);
    case fieldName:
                FieldType value;
                immutable bool valid = validateImplFieldValue!fieldName(kvp.value, value, error);
                if (!valid)
                    return false;

                mixin(`data.` ~ fieldName ~ ` = value;`);

                static foreach (isSetField; IsSetCollection!(Data).tupleof)
                    static if (__traits(identifier, isSetField) == fieldName)
                        mixin(`isSetCollection.` ~ fieldName ~ ` = true;`);
                return true;
            }
        }

    default:
        static if (!allowExtraFields)
        {
            output.ok = false;
            output.errors[idx] = kvp.key ~ ": unexpected extra field";
            return false;
        }
        return true;
    }

    assert(false, "This statement should be unreachable.");
}

private bool validateImplFieldValue(string fieldName, T)(hstring sValue, out T value, out ValidationError error)
{
    pragma(inline, true);

    import std.conv : to;

    try
    {
        value = sValue.to!T;
    }
    catch (Exception ex)
    {
        error = ValidationError(fieldName, "Invalid " ~ T.stringof ~ " value");
        return false;
    }

    return true;
}

private enum isRangeOfKeyValuePairs(InputRange) = (
        isInputRange!InputRange
            && is(ElementType!InputRange == KeyValuePair)
    );
