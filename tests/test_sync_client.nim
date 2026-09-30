import std/[unittest, tables, options]
import results
import jev_nim_client
import jev_nim_client/syncclient
import support
import fake_transports

suite "sync client":
  test "systemOne uses fake transport":
    syncTransportCalls = 0
    let client = newJevClient(
      apiKey = testApiKey,
      baseUrl = "https://example.test",
      executor = some SyncRequestExecutor(fakeSyncTransport),
    ).get()
    defer:
      client.close()
    let result = client.systemOne("Help!", sampleQuestions()).get()
    check syncTransportCalls == 1
    check result.noul("is_urgent").get().noul == 0.95

  test "listModels retries 429 then succeeds":
    flakyTransportCalls = 0
    var policy = defaultRetryPolicy()
    policy.maxRetries = 1
    policy.backoffInitial = 0.0
    policy.backoffJitter = 0.0
    policy.totalBudgetSec = some(30.0)
    let client = newJevClient(
      apiKey = testApiKey,
      baseUrl = "https://example.test",
      retryPolicy = policy,
      executor = some SyncRequestExecutor(flakySyncTransport),
    ).get()
    defer:
      client.close()
    let models = client.listModels().get()
    check flakyTransportCalls == 2
    check models.models[0].name == "jev-latest"

  test "buildDefaultHeaders":
    check "authorization" in buildDefaultHeaders(typesafeProfile, testApiKey)
    check "authorization" notin buildDefaultHeaders(ollamaProfile, "")

suite "sync client providers":
  test "typesafe sends authorization and posts systemone":
    resetLastRequestFlags()
    let client = newJevClient(
      apiKey = testApiKey,
      baseUrl = "https://example.test",
      executor = some SyncRequestExecutor(recordingSyncTransport),
    ).get()
    defer:
      client.close()
    discard client.systemOne("Help!", sampleQuestions()).get()
    check lastRequestHadAuth
    check lastRequestSystemOnePost

  test "ollama omits authorization by default":
    resetLastRequestFlags()
    let client = newJevClient(
      provider = ollama,
      baseUrl = "http://127.0.0.1:11434",
      executor = some SyncRequestExecutor(recordingSyncTransport),
    ).get()
    defer:
      client.close()
    discard client.systemOne("Help!", sampleQuestions()).get()
    check not lastRequestHadAuth

  test "keep_alive rejected for typesafe at systemOne":
    let client = newJevClient(
      apiKey = testApiKey,
      baseUrl = "https://example.test",
      executor = some SyncRequestExecutor(recordingSyncTransport),
    ).get()
    defer:
      client.close()
    var opts = defaultRequestOptions()
    opts.keepAlive = some(keepAliveSeconds(0))
    check client.systemOne("Help!", sampleQuestions(), opts).isErr

  test "ollama listModels hits tags endpoint":
    resetLastRequestFlags()
    let client = newJevClient(
      provider = ollama,
      baseUrl = "http://127.0.0.1:11434",
      executor = some SyncRequestExecutor(ollamaTagsTransport),
    ).get()
    defer:
      client.close()
    let models = client.listModels().get()
    check models.models.len == 2
    check models.models[0].name == "nimble:latest"
    check lastRequestTagsGet
