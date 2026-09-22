import std/[asyncdispatch, unittest, tables, json, options, strutils]
import jev_nim_client
import jev_nim_client/wire
import jev_nim_client/retry
import jev_nim_client/requestloop

const
  sampleSystemOneResponse = """
{
  "model": "jev-1.13.0",
  "usage": { "input_tokens": 296, "output_tokens": 20 },
  "answers": {
    "is_urgent": { "type": "noul", "noul": 0.95 },
    "department": {
      "type": "choice",
      "choice": "billing",
      "probabilities": { "billing": 0.88, "technical": 0.12 },
      "confidence": 0.81
    },
    "frustration": {
      "type": "score",
      "score": 1.05,
      "legend": { "0": "Calm", "1": "Frustrated", "2": "Very angry" },
      "probabilities": { "0": 0.0, "1": 0.95, "2": 0.05 },
      "confidence": 0.92
    }
  }
}
"""

const sampleModelsResponse = """
{
  "models": [
    {
      "name": "jev-latest",
      "description": "Latest stable Jev",
      "release_date": "2026-01-01"
    }
  ]
}
"""

var syncTransportCalls = 0
var flakyTransportCalls = 0
var asyncTransportCalls = 0

proc fakeSyncTransport(
    verb, url, body: string; headers: Table[string, string]; timeoutSec: float,
): Result[RawResponse, JevFailure] {.gcsafe.} =
  inc syncTransportCalls
  doAssert verb == "POST"
  doAssert url.endsWith("/v1/systemone")
  var hdrs = initTable[string, string]()
  hdrs["x-typesafe-request-id"] = "abc"
  ok[RawResponse, JevFailure](RawResponse(
    status: 200, body: sampleSystemOneResponse, headers: hdrs,
  ))

proc flakySyncTransport(
    verb, url, body: string; headers: Table[string, string]; timeoutSec: float,
): Result[RawResponse, JevFailure] {.gcsafe.} =
  inc flakyTransportCalls
  if flakyTransportCalls == 1:
    var hdrs = initTable[string, string]()
    hdrs["retry-after-ms"] = "1"
    ok[RawResponse, JevFailure](RawResponse(status: 429, body: "slow down", headers: hdrs))
  else:
    ok[RawResponse, JevFailure](RawResponse(
      status: 200, body: sampleModelsResponse, headers: initTable[string, string](),
    ))

proc fakeAsyncTransport(
    verb, url, body: string; headers: Table[string, string]; timeoutSec: float,
): Future[Result[RawResponse, JevFailure]] {.async.} =
  inc asyncTransportCalls
  ok[RawResponse, JevFailure](RawResponse(
    status: 200, body: sampleSystemOneResponse, headers: initTable[string, string](),
  ))

test "encode all question types":
  var questions = initOrderedTable[string, Question]()
  questions["is_urgent"] = noul("Does this convey urgency?")
  var deptCriteria = initOrderedTable[string, string]()
  deptCriteria["billing"] = "Payments and refunds"
  deptCriteria["technical"] = "Bugs and outages"
  questions["department"] = choice("Which team should handle this?", deptCriteria)
  var toneCriteria = initOrderedTable[string, string]()
  toneCriteria["calm"] = "Calm"
  toneCriteria["angry"] = "Angry"
  questions["tone"] = choice("What is the tone?", toneCriteria)
  questions["tone"].choice.criteria["angry"] = none(JsonContent)
  questions["frustration"] = score(
    "How frustrated is the customer?", "Calm", "Frustrated", "Very angry",
  )

  let body = encodeSystemOneBody("Help!", "jev-latest", questions)
  check body["model"].getStr() == "jev-latest"
  check body["state"].getStr() == "Help!"
  check body["questions"]["is_urgent"]["type"].getStr() == "noul"
  check body["questions"]["department"]["type"].getStr() == "choice"
  check body["questions"]["tone"]["criteria"]["angry"].kind == JNull
  check body["questions"]["frustration"]["criteria"].len == 3

test "decode system one response":
  var headers = initTable[string, string]()
  headers["x-typesafe-request-id"] = "req_123"
  let decoded = decodeSystemOneResponse(sampleSystemOneResponse, headers).unwrap()
  check decoded.model == "jev-1.13.0"
  check decoded.requestId == "req_123"
  check decoded.usage.inputTokens == some(296)
  check decoded.noul("is_urgent").unwrap().noul == 0.95
  check decoded.choice("department").unwrap().choice == "billing"
  check decoded.score("frustration").unwrap().score == 1.05

test "validate questions rejects empty and short score rubrics":
  var empty = initOrderedTable[string, Question]()
  check validateQuestions(empty).isErr
  empty["x"] = score("Rate this", "Only one")
  check validateQuestions(empty).isErr

test "retry policy respects retry-after and skips 401":
  var policy = defaultRetryPolicy()
  policy.maxRetries = 2
  policy.backoffInitial = 0.0
  policy.backoffJitter = 0.0
  policy.totalBudgetSec = some(60.0)
  var headers = initTable[string, string]()
  headers["retry-after"] = "2"
  let (retry429, delay429) = shouldRetryHttp(policy, 0, 429, headers, 0.0)
  check retry429
  check delay429 >= 2.0
  let (retry401, _) = shouldRetryHttp(policy, 0, 401, headers, 0.0)
  check not retry401

test "retry budget stops further attempts":
  var policy = defaultRetryPolicy()
  policy.maxRetries = 5
  policy.backoffInitial = 10.0
  policy.backoffJitter = 0.0
  policy.totalBudgetSec = some(5.0)
  let headers = initTable[string, string]()
  let (retry, _) = shouldRetryHttp(policy, 0, 503, headers, 4.0)
  check not retry

test "sync client uses fake transport":
  syncTransportCalls = 0
  let client = newJevClient(
    apiKey = "ts_test_key_1234567890",
    baseUrl = "https://example.test",
    executor = some SyncRequestExecutor(fakeSyncTransport),
  ).unwrap()
  defer:
    client.close()

  var questions = initOrderedTable[string, Question]()
  questions["is_urgent"] = noul("Does this convey urgency?")
  let result = client.systemOne("Help!", questions).unwrap()
  check syncTransportCalls == 1
  check result.noul("is_urgent").unwrap().noul == 0.95

test "sync client retries 429 then succeeds":
  flakyTransportCalls = 0
  var policy = defaultRetryPolicy()
  policy.maxRetries = 1
  policy.backoffInitial = 0.0
  policy.backoffJitter = 0.0
  policy.totalBudgetSec = some(30.0)

  let client = newJevClient(
    apiKey = "ts_test_key_1234567890",
    baseUrl = "https://example.test",
    retryPolicy = policy,
    executor = some SyncRequestExecutor(flakySyncTransport),
  ).unwrap()
  defer:
    client.close()

  let models = client.listModels().unwrap()
  check flakyTransportCalls == 2
  check models.models[0].name == "jev-latest"

test "async client uses fake transport":
  asyncTransportCalls = 0
  let client = newAsyncJevClient(
    apiKey = "ts_test_key_1234567890",
    baseUrl = "https://example.test",
    executor = some AsyncRequestExecutor(fakeAsyncTransport),
  ).unwrap()
  defer:
    client.close()
  var questions = initOrderedTable[string, Question]()
  questions["is_urgent"] = noul("Does this convey urgency?")
  let result = waitFor(client.systemOne("Help!", questions)).unwrap()
  check asyncTransportCalls == 1
  check result.noul("is_urgent").unwrap().noul == 0.95

test "raiseFailure maps 401 to authentication error":
  let failure = apiFailure(401, "nope", "POST https://example.test/v1/systemone", initTable[string, string]())
  var gotAuth = false
  try:
    raiseFailure(failure)
  except JevAuthenticationError:
    gotAuth = true
  except CatchableError:
    discard
  check gotAuth
