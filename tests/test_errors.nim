import std/[unittest, tables, options]
import results
import jev_nim_client/errors

suite "errors validateApiKey":
  test "rejects empty and whitespace keys":
    check validateApiKey("").isErr
    check validateApiKey("  ").isErr
    check validateApiKey("key with space").isErr

  test "accepts stripped key":
    check validateApiKey("  ts_abc123  ").get() == "ts_abc123"

suite "errors messages":
  test "parseApiErrorMessage reads ollama and nested errors":
    check parseApiErrorMessage("""{"error":"model not found"}""") == "model not found"
    check parseApiErrorMessage("""{"error":{"message":"bad"}}""") == "bad"
    check parseApiErrorMessage("plain text") == "plain text"
    check parseApiErrorMessage("") == ""

  test "message uses api error body when present":
    let f = apiFailure(404, """{"error":"missing"}""", "GET /x", initTable[string, string]())
    check f.message() == "missing"

  test "message for validation and timeout failures":
    check validationFailure("nope").message() == "nope"
    check timeoutFailure(3.5).message() == "request timed out after 3.5s"
    check responseFailure("answers.x", "bad type").message() ==
      "invalid response at answers.x: bad type"

  test "requestId from api failure headers":
    var headers = initTable[string, string]()
    headers["X-TypeSafe-Request-Id"] = "rid-1"
    let f = apiFailure(500, "", "POST /x", headers)
    check f.requestId() == some("rid-1")

suite "errors parseRetryAfterMs":
  test "parses retry-after-ms and retry-after seconds":
    var h1 = initTable[string, string]()
    h1["retry-after-ms"] = "1500"
    check parseRetryAfterMs(h1) == some(1500)
    var h2 = initTable[string, string]()
    h2["Retry-After"] = "2"
    check parseRetryAfterMs(h2) == some(2000)

suite "errors raiseFailure":
  test "maps status codes to typed exceptions":
    template checkRaises(status: int; T: typedesc) =
      block:
        var caught = false
        try:
          raiseFailure(apiFailure(
            status, "", "POST https://example.test", initTable[string, string](),
          ))
        except T:
          caught = true
        except CatchableError:
          discard
        check caught

    checkRaises(400, JevBadRequestError)
    checkRaises(401, JevAuthenticationError)
    checkRaises(403, JevPermissionDeniedError)
    checkRaises(404, JevNotFoundError)
    checkRaises(422, JevUnprocessableEntityError)
    checkRaises(429, JevRateLimitError)
    checkRaises(503, JevInternalServerError)

  test "maps timeout to JevTimeoutError":
    var caught = false
    try:
      raiseFailure(timeoutFailure(1.0))
    except JevTimeoutError:
      caught = true
    except CatchableError:
      discard
    check caught
