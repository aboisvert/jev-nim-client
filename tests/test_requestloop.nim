import std/[unittest, tables, options]
import results
import jev_nim_client/requestloop
import jev_nim_client/retry
import jev_nim_client/errors
import fake_transports

suite "requestloop":
  test "classifyHttpResponse accepts 2xx and rejects errors":
    let okResp = RawResponse(status: 200, body: "{}", headers: initTable[string, string]())
    check classifyHttpResponse(okResp, "GET /x").isOk
    let errResp = RawResponse(status: 400, body: "bad", headers: initTable[string, string]())
    check classifyHttpResponse(errResp, "POST /x").isErr

  test "executeWithRetry retries 429 then succeeds":
    flakyTransportCalls = 0
    var policy = defaultRetryPolicy()
    policy.maxRetries = 1
    policy.backoffInitial = 0.0
    policy.backoffJitter = 0.0
    policy.totalBudgetSec = some(30.0)
    proc noSleep(_: float) {.gcsafe.} = discard
    let result = executeWithRetry(
      policy,
      SyncRequestExecutor(flakySyncTransport),
      noSleep,
      "GET",
      "https://example.test/v1/models",
      "",
      initTable[string, string](),
      5.0,
      "GET https://example.test/v1/models",
    )
    check result.isOk
    check flakyTransportCalls == 2

  test "executeWithRetry returns connection failure without retry when disabled":
    var policy = defaultRetryPolicy()
    policy.maxRetries = 2
    policy.retryConnection = false
    proc failTransport(
        verb, url, body: string; headers: Table[string, string]; timeoutSec: float,
    ): Result[RawResponse, JevFailure] {.gcsafe.} =
      err(connectionFailure("down"))
    proc noSleep(_: float) {.gcsafe.} = discard
    let result = executeWithRetry(
      policy,
      SyncRequestExecutor(failTransport),
      noSleep,
      "GET",
      "https://example.test",
      "",
      initTable[string, string](),
      1.0,
      "GET https://example.test",
    )
    check result.isErr
