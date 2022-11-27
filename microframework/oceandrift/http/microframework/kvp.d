/++
    Key+Value Pair implementation
 +/
module oceandrift.http.microframework.kvp;

import oceandrift.http.message : hstring;

@safe pure nothrow @nogc:

/// Key+Value Pair
struct KeyValuePair
{
    /// Key
    hstring key;

    /// Associated value
    hstring value;
}

/++
    Determines whether a [KeyValuePair] with the specified key exists in the passed array

    Returns:
        true = if a matching KeyValuePair was found
 +/
bool contains(KeyValuePair[] array, hstring key)
{
    foreach (kvp; array)
        if (kvp.key == key)
            return true;

    return false;
}

/++
    Determines whether a [KeyValuePair] with the specified key exists in the passed array

    Also makes it available through an out parameter.

    Params:
        result = value of the KeyValuePair – only valid when this function returned true

    Returns:
        true = if a matching KeyValuePair was found
 +/
bool tryGet(KeyValuePair[] array, hstring key, out hstring result)
{
    foreach (kvp; array)
    {
        if (kvp.key == key)
        {
            result = kvp.value;
            return true;
        }
    }

    return false;
}

/++
    Returns the value of the [KeyValuePair] with the specified key in the passed array
 +/
hstring get(KeyValuePair[] array, hstring key, hstring substituteIfNotFound = null)
{
    foreach (kvp; array)
        if (kvp.key == key)
            return kvp.value;

    return substituteIfNotFound;
}

bool empty(const KeyValuePair[] array)
{
    return (array.length == 0);
}

KeyValuePair front(KeyValuePair[] array)
{
    return array[0];
}

void popFront(ref KeyValuePair[] array)
{
    array = array[1 .. $];
}
