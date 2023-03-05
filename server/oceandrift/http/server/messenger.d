/++
    HTTP request parsing and response sending functionality

    $(NOTE
        While code in this module is mostly `public` (so you can happily use it to hack cool things together!),
        it’s rather to be considered an implementation detail and subject to potentially breaking changes.
    )
 +/
module oceandrift.http.server.messenger;

import oceandrift.http.message;
import socketplate.connection;
import std.conv : to;
import std.datetime : dur;

@safe:

enum CRLF = "\r\n";
enum CRLFCRLF = CRLF ~ CRLF;
enum requestInitialBufferSize = 2 * 1024;
enum requestMaxBodySize = (1024 ^^ 2) * 16;
enum bodyChunkSize = 1024 * 2;

pragma(msg, "Max request body size: " ~ requestMaxBodySize.to!string);

/// Returns: 0 on success
int parseRequest(ref SocketConnection connection, out Request request)
{
    import httparsed;

    enum statusPartial = -1 * ParserError.partial;

    ubyte[] buffer = new ubyte[](requestInitialBufferSize);

    // Create header parser (httparsed)
    auto parser = initParser!RequestTransformer();
    parser.setup();

    int httparsedStatus = 0;
    ptrdiff_t bytesReadTotalWhileParsingHeaders = 0;
    uint headerParserLastPos = 0;

    // parse header
    while (true)
    {
        // wait for data & read into buffer
        ptrdiff_t bytesRead = connection.receive(
            buffer[bytesReadTotalWhileParsingHeaders .. $],
        );

        if ((bytesRead == socketERROR) || (bytesRead == 0))
            return -1;

        bytesReadTotalWhileParsingHeaders += bytesRead;

        // call httparsed
        () @trusted {
            httparsedStatus = parser.parseRequest(buffer[0 .. bytesReadTotalWhileParsingHeaders], headerParserLastPos);
        }();

        if (httparsedStatus == statusPartial) // httparsed reports partial data; grow buffer and retry
        {
            if (buffer.length >= 16_384)
                throw new Exception("Request headers too big.");

            // grow buffer
            buffer.length += buffer.length;
        }
        else if (httparsedStatus >= 0) // fine
            break;
        else // error (in httparsed)
            return httparsedStatus;
    }

    request = parser.getData();

    // -- Parse body

    auto reqBody = MultiBuffer();

    hstring[] headerContentLength = request.getHeader!"Content-Length"();
    if (headerContentLength.length == 0)
    {
        if (request.hasHeader!"Transfer-Encoding")
            return 501; // unsupported because not implemented

        // empty body
        return 0;
    }

    buffer = buffer[httparsedStatus .. $];

    // More than one “Content-Length” header?
    if (headerContentLength.length > 1)
        return 400; // am I supposed to guess which one’s correct, huh?!

    // Parse content-length header
    size_t contentLength = 0;
    try
        contentLength = headerContentLength[0].to!size_t;
    catch (Exception) // not a positive integer
        return 400;

    // Within max length
    if (contentLength > requestMaxBodySize)
        throw new Exception("Request too big; limit: " ~ requestMaxBodySize.to!string); // TODO

    // Determine number of body bytes already read
    immutable size_t alreadyReadBody = bytesReadTotalWhileParsingHeaders - headerParserLastPos;
    // Write them to the body object
    reqBody.write(buffer[0 .. alreadyReadBody]);

    // Determine number of bytes left to read (for the body)
    size_t contentLengthLeft = contentLength - alreadyReadBody;

    // If there’s something left, first use what’s left from the already allocated buffer,
    // then allocate a new one for the rest
    if (contentLengthLeft > 0)
    {
        buffer = buffer[alreadyReadBody .. $];
        if (contentLengthLeft <= buffer.length)
            buffer = buffer[0 .. contentLengthLeft];

        try
        {
            const(ubyte)[] bufferReceived = connection.receiveAll(buffer);
            contentLengthLeft -= bufferReceived.length;
            reqBody.write(bufferReceived);
        }
        catch (SocketTimeoutException ex)
            return 408;

        // Still a few body bytes left?
        if (contentLengthLeft > 0)
        {
            // Allocate a new buffer to fit the whole rest of the request body at once
            buffer = new ubyte[](contentLengthLeft);

            try
                buffer = connection.receiveAll(buffer);
            catch (SocketTimeoutException ex)
                return 408;

            // Append buffer to the body object
            reqBody.write(buffer);
        }
    }

    // Store body in request object
    parser.onBody(reqBody);
    request = parser.getData();

    // Report success
    return 0;
}

void sendResponse(ref SocketConnection connection, Response response)
{
    scope (exit)
        if (response.body !is null)
            response.body.close();

    connection.send("HTTP/1.1 ");
    connection.send(response.statusCode.to!string);
    connection.send(" ");
    connection.send(
        (response.reasonPhrase.length > 0)
            ? response.reasonPhrase
            : getReasonPhrase(response.statusCode)
    );
    connection.send(CRLF);

    foreach (Header header; response.headers)
    {
        foreach (value; header.values)
        {
            connection.send(header.name);
            connection.send(": ");
            connection.send(value);
            connection.send(CRLF);
        }
    }

    // no body?
    if (response.body is null)
    {
        // set content-length header to zero if it hasn’t been set yet
        // don’t override because HEAD requests
        if (!response.hasHeader!"Content-Length")
            response.setHeader!"Content-Length" = "0";

        connection.send(CRLFCRLF);
        return;
    }

    // no known body length?
    immutable long contentLength = response.body.knownLength;
    if (contentLength < 0)
    {
        // no, send chunked
        connection.send("transfer-encoding: chunked");
        connection.send(CRLFCRLF);
        sendResponseBodyChunked(connection, response.body);
    }
    else
    {
        // yes, send content-length
        connection.send("content-length: ");
        connection.send(contentLength.to!hstring);
        connection.send(CRLFCRLF);
        sendResponseBodyAtOnce(connection, response.body);
    }
}

void sendResponse(ref SocketConnection connection, int status, string reasonPhrase)
{
    connection.send("HTTP/1.1 ");
    connection.send(status.to!string);
    connection.send(" ");
    connection.send(reasonPhrase);
    connection.send(CRLF);
}

private void sendResponseBodyAtOnce(ref SocketConnection connection, DataQ bodyData)
{
    ubyte[bodyChunkSize] buffer;
    while (!bodyData.empty)
    {
        immutable size_t bytesRead = bodyData.read(buffer);
        connection.send(buffer[0 .. bytesRead]);
    }
}

private void sendResponseBodyChunked(ref SocketConnection connection, DataQ bodyData)
{
    import std.string : format, sformat;

    enum chunkLengthMaxStringLength = format("%X", size_t.max).length;

    char[chunkLengthMaxStringLength] chunkLengthBuffer;
    ubyte[bodyChunkSize] buffer;

    while (!bodyData.empty)
    {
        immutable size_t bytesRead = bodyData.read(buffer);
        const ubyte[] chunk = buffer[0 .. bytesRead];

        const char[] chunkLength = sformat!"%X"(chunkLengthBuffer, chunk.length);
        connection.send(chunkLength);
        connection.send(CRLF);

        connection.send(chunk);
        connection.send(CRLF);
    }
}

bool isKeepAlive(Request request)
{
    enum kaValue = LowerCaseToken.makeConverted("keep-alive");

    if (request.protocol == "HTTP/1.1")
    {
        if (!request.hasHeader!"Connection")
            return true;

        const hstring[] h = request.getHeader!"Connection";

        foreach (value; h)
            if (value.equalsCaseInsensitive(kaValue))
                return true;
    }
    else if (request.protocol == "HTTP/1.0")
    {
        const hstring[] h = request.getHeader!"Connection";

        foreach (value; h)
            if (value.equalsCaseInsensitive(kaValue))
                return true;
    }

    return false;
}
