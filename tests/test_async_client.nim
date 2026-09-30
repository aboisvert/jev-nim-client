import std/[asyncdispatch, unittest, tables, options]
import results
import jev_nim_client
import support
import fake_transports

suite "async client":
  test "systemOne uses fake transport":
    asyncTransportCalls = 0
    let client = newAsyncJevClient(
      apiKey = testApiKey,
      baseUrl = "https://example.test",
      executor = some AsyncRequestExecutor(fakeAsyncTransport),
    ).get()
    defer:
      client.close()
    let result = waitFor(client.systemOne("Help!", sampleQuestions())).get()
    check asyncTransportCalls == 1
    check result.noul("is_urgent").get().noul == 0.95
