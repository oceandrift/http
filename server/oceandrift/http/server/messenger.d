/++
    HTTP request parsing and response sending functionality

    $(NOTE
        While code in this module is mostly `public` (so you can happily use it to hack cool things together!)
        it’s rather to be considered an implementation detail and subject to potentially breaking changes.
    )
 +/
module oceandrift.http.server.messenger;

import oceandrift.http.message;
import std.conv : to;
import std.datetime : dur;
import vibe.core.net;
import vibe.core.stream;

@safe:

enum CRLF = "\r\n";
enum CRLFCRLF = CRLF ~ CRLF;
enum requestInitialBufferSize = 2 * 1024;
enum requestMaxBodySize = (1024 ^^ 2) * 16;

pragma(msg, "Max request body size: " ~ requestMaxBodySize.to!string);

/// Returns: 0 on success
int parseRequest(TCPConnection connection, out Request request) //int parseRequest(TCPConnection connection, ubyte[] defaultBuffer, out Request request)
{
    import httparsed;

    enum statusPartial = -1 * ParserError.partial;

    ubyte[] buffer = new ubyte[](requestInitialBufferSize);

    // Create header parser (httparsed)
    auto parser = initParser!RequestTransformer();
    parser.setup();

    int httparsedStatus = 0;
    size_t bytesReadTotalWhileParsingHeaders = 0;
    uint headerParserLastPos = 0;

    // parse header
    while (true)
    {
        // wait for data
        if (!connection.waitForData(dur!"minutes"(2)))
            return 408;

        // read buffer
        size_t bytesRead = connection.read(
            buffer[bytesReadTotalWhileParsingHeaders .. $],
            IOMode.once
        );
        bytesReadTotalWhileParsingHeaders += bytesRead;

        // call httparsed
        delegate() @trusted {
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
            immutable size_t bytesRead = connection.read(buffer, IOMode.all);
            contentLengthLeft -= bytesRead;
            reqBody.write(buffer[0 .. bytesRead]);
        }
        catch (Exception ex)
            return 408;

        // Still a few body bytes left?
        if (contentLengthLeft > 0)
        {
            // Allocate a new buffer to fit the whole rest of the request body at once
            buffer = new ubyte[](contentLengthLeft);

            try
                connection.read(buffer, IOMode.all);
            catch (Exception ex)
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

void sendResponse(TCPConnection connection, Response response)
{
    connection.write("HTTP/1.1 ");
    connection.write(response.statusCode.to!string);
    connection.write(" ");
    connection.write(
        (response.reasonPhrase.length > 0)
            ? response.reasonPhrase.data
            : getReasonPhrase(response.statusCode).data
    );
    connection.write(CRLF);

    foreach (Header header; response.headers)
    {
        foreach (value; header.values)
        {
            connection.write(header.name.data);
            connection.write(": ");
            connection.write(value.data);
            connection.write(CRLF);
        }
    }
    connection.write("content-length: ");
    connection.write(response.body_.dataLength.to!string);
    connection.write(CRLF);

    connection.write(CRLF);
    foreach (data; response.body_)
        connection.write(data.data);

    connection.flush();
}

void sendResponse(TCPConnection connection, int status, hstring reasonPhrase)
{
    connection.write("HTTP/1.1 ");
    connection.write(status.to!string);
    connection.write(" ");
    connection.write(reasonPhrase.data);
    connection.write(CRLF);
    connection.flush();
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
