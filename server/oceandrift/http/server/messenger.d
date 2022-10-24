module oceandrift.http.server.messenger;

import oceandrift.http.message;
import std.conv : to;
import std.datetime : dur;
import vibe.core.net;
import vibe.core.stream;

@safe:

enum CRLF = "\r\n";
enum CRLFCRLF = CRLF ~ CRLF;
enum requestMaxBodySize = (1024 ^^ 2) * 16;

pragma(msg, "Max request body size: " ~ requestMaxBodySize.to!string);

/// Returns: 0 on success
int parseRequest(TCPConnection connection, ubyte[] defaultBuffer, out Request request)
{
    import httparsed;

    enum statusPartial = -1 * ParserError.partial;

    ubyte[] buffer = defaultBuffer;

    auto parser = initParser!RequestTransformer();
    parser.setup();
    int status = 0;
    uint headerParserLastPos = 0;
    {
        int bytesReadTotal = 0;

        // parse header
        while (true)
        {
            // wait for data
            if (!connection.waitForData(dur!"minutes"(2)))
                return 408;

            // read buffer
            size_t bytesRead = connection.read(buffer[bytesReadTotal .. $], IOMode.once);
            bytesReadTotal += bytesRead;

            delegate() @trusted {
                status = parser.parseRequest(buffer[0 .. bytesReadTotal], headerParserLastPos);
            }();

            if (status == statusPartial)
            {
                if (buffer.length >= 16_384)
                    throw new Exception("Request headers too big.");

                buffer.length += buffer.length;
            }
            else if (status >= 0)
                break;
            else
                return status;
        }
    }

    request = parser.getData();
    auto reqBody = Body();

    if (!request.hasHeader!"Content-Length")
    {
        if (request.hasHeader!"Transfer-Encoding")
            return 501;

        // empty body
        return 0;
    }

    buffer = buffer[headerParserLastPos .. $];

    hstring[] headerContentLength = request.getHeader!"Content-Length"();
    if (headerContentLength.length > 1)
        return 400; // am I supposed to guess which one’s correct, huh?!

    size_t contentLength = headerContentLength[0].to!size_t;

    if (contentLength > requestMaxBodySize)
        throw new Exception("Request too big; limit: " ~ requestMaxBodySize.to!string);

    if (contentLength > buffer.length)
    {
        reqBody.write(buffer);

        immutable size_t contentLengthLeft = contentLength - buffer.length;
        buffer = new ubyte[](contentLengthLeft);

        try
            connection.read(buffer, IOMode.all);
        catch (Exception ex)
            return 408;

        reqBody.write(buffer);
    }
    else
    {
        if (contentLength > 0)
            reqBody.write(buffer[0 .. contentLength]);
    }

    parser.onBody(reqBody);
    request = parser.getData();

    return 0;
}

void sendResponse(TCPConnection connection, Response response)
{
    connection.write("HTTP/1.1 ");
    connection.write(response.statusCode.to!string);
    connection.write(
        (response.reasonPhrase.length > 0)
            ? response.reasonPhrase
            : getReasonPhrase(response.statusCode)
    );
    connection.write(CRLF);

    foreach (Header header; response.headers)
    {
        foreach (value; header.values)
        {
            connection.write(header.name);
            connection.write(": ");
            connection.write(value);
            connection.write(CRLF);
        }
    }
    connection.write("content-length: ");
    connection.write(response.body_.data.length.to!string);
    connection.write(CRLF);

    connection.write(CRLF);
    connection.write(response.body_.data);
    connection.flush();
}

void sendResponse(TCPConnection connection, int status, string reasonPhrase)
{
    connection.write("HTTP/1.1 ");
    connection.write(status.to!string);
    connection.write(" ");
    connection.write(reasonPhrase);
    connection.write(CRLF);
    connection.flush();
}

bool isKeepAlive(scope Request request)
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
