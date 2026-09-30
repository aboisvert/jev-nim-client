## Injectable HTTP transports for client and request-loop tests.

import std/[asyncdispatch, tables, strutils]
import jev_nim_client
import jev_nim_client/requestloop
import support

var syncTransportCalls* = 0
var flakyTransportCalls* = 0
var asyncTransportCalls* = 0
var lastRequestHadAuth* = false
var lastRequestSystemOnePost* = false
var lastRequestTagsGet* = false

proc resetLastRequestFlags*() =
  lastRequestHadAuth = false
  lastRequestSystemOnePost = false
  lastRequestTagsGet = false

proc recordingSyncTransport*(
    verb, url, body: string; headers: Table[string, string]; timeoutSec: float,
): Result[RawResponse, JevFailure] {.gcsafe.} =
  lastRequestHadAuth = "authorization" in headers
  lastRequestSystemOnePost = verb == "POST" and url.endsWith("/v1/systemone")
  lastRequestTagsGet = verb == "GET" and url.endsWith("/api/tags")
  var hdrs = initTable[string, string]()
  ok(RawResponse(status: 200, body: sampleSystemOneResponse, headers: hdrs))

proc fakeSyncTransport*(
    verb, url, body: string; headers: Table[string, string]; timeoutSec: float,
): Result[RawResponse, JevFailure] {.gcsafe.} =
  inc syncTransportCalls
  doAssert verb == "POST"
  doAssert url.endsWith("/v1/systemone")
  var hdrs = initTable[string, string]()
  hdrs["x-typesafe-request-id"] = "abc"
  ok(RawResponse(
    status: 200, body: sampleSystemOneResponse, headers: hdrs,
  ))

proc flakySyncTransport*(
    verb, url, body: string; headers: Table[string, string]; timeoutSec: float,
): Result[RawResponse, JevFailure] {.gcsafe.} =
  inc flakyTransportCalls
  if flakyTransportCalls == 1:
    var hdrs = initTable[string, string]()
    hdrs["retry-after-ms"] = "1"
    ok(RawResponse(status: 429, body: "slow down", headers: hdrs))
  else:
    ok(RawResponse(
      status: 200, body: sampleModelsResponse, headers: initTable[string, string](),
    ))

proc fakeAsyncTransport*(
    verb, url, body: string; headers: Table[string, string]; timeoutSec: float,
): Future[Result[RawResponse, JevFailure]] {.async.} =
  inc asyncTransportCalls
  ok(RawResponse(
    status: 200, body: sampleSystemOneResponse, headers: initTable[string, string](),
  ))

proc ollamaTagsTransport*(
    verb, url, body: string; headers: Table[string, string]; timeoutSec: float,
): Result[RawResponse, JevFailure] {.gcsafe.} =
  lastRequestTagsGet = verb == "GET" and url.endsWith("/api/tags")
  ok(RawResponse(
    status: 200,
    body: """{"models":[{"name":"nimble:latest"},{"name":"other"}]}""",
    headers: initTable[string, string](),
  ))
