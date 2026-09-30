import std/[unittest, tables, json, options, strutils]
import jev_nim_client
import jev_nim_client/wire
import jev_nim_client/syncclient
import support

suite "wire encode":
  test "encode all question types for typesafe":
    let body = encodeSystemOneBody(
      typesafeProfile, "Help!", "jev-latest", fullQuestionSet(),
    ).get()
    check body["model"].getStr() == "jev-latest"
    check body["state"].getStr() == "Help!"
    check body["questions"]["is_urgent"]["type"].getStr() == "noul"
    check body["questions"]["department"]["type"].getStr() == "choice"
    check body["questions"]["tone"]["criteria"]["angry"].kind == JNull
    check body["questions"]["frustration"]["criteria"].len == 3

  test "encode noul criteria and structured state":
    var questions = initOrderedTable[string, Question]()
    questions["q"] = noul(
      "Yes?",
      noulCriteria("Customer agrees", "Customer declines"),
    )
    var stateObj = initOrderedTable[string, JsonValue]()
    stateObj["ticket"] = jsonStr("open")
    let state = jsonContentObj(stateObj)
    let body = encodeSystemOneBody(typesafeProfile, state, "m", questions).get()
    check body["state"].kind == JObject
    check body["questions"]["q"]["criteria"]["true"].getStr() == "Customer agrees"

  test "ollama encodes string criteria and keep_alive":
    var questions = sampleQuestions()
    let bodyDuration = encodeSystemOneBody(
      ollamaProfile, "Help!", "nimble", questions, some(keepAliveDuration("5m")),
    ).get()
    check bodyDuration["keep_alive"].getStr() == "5m"
    let bodySeconds = encodeSystemOneBody(
      ollamaProfile, "Help!", "nimble", questions, some(keepAliveSeconds(0)),
    ).get()
    check bodySeconds["keep_alive"].getFloat() == 0.0

  test "keep_alive rejected for typesafe at encode time":
    let r = encodeSystemOneBody(
      typesafeProfile, "Hi", "jev-latest", sampleQuestions(),
      some(keepAliveDuration("5m")),
    )
    check r.isErr

suite "wire validate":
  test "validate questions rejects empty and short score rubrics":
    var empty = initOrderedTable[string, Question]()
    check validateQuestions(typesafeProfile, empty).isErr
    empty["x"] = score("Rate this", "Only one")
    check validateQuestions(typesafeProfile, empty).isErr

  test "ollama rejects blank string state":
    check validateState(ollamaProfile, content("   ")).isErr

  test "ollama rejects structured choice criteria":
    var criteria = initOrderedTable[string, Option[JsonContent]]()
    criteria["a"] = some(jsonContentObj(initOrderedTable[string, JsonValue]()))
    criteria["b"] = some(content("plain"))
    var qs = initOrderedTable[string, Question]()
    qs["q"] = choice("Pick one", criteria)
    check validateQuestions(ollamaProfile, qs).isErr

  test "ollama rejects too many choice options":
    var criteria = initOrderedTable[string, Option[JsonContent]]()
    for i in 0 .. 26:
      criteria["k" & $i] = some(content("x"))
    var qs = initOrderedTable[string, Question]()
    qs["q"] = choice("Pick", criteria)
    check validateQuestions(ollamaProfile, qs).isErr

  test "ollama rejects oversized request body":
    var qs = initOrderedTable[string, Question]()
    qs["q"] = noul("Is this urgent?")
    let huge = content("x".repeat(64 * 1024))
    check encodeSystemOneBody(ollamaProfile, huge, "nimble", qs).isErr

suite "wire decode":
  test "decode system one response":
    var headers = initTable[string, string]()
    headers["x-typesafe-request-id"] = "req_123"
    let decoded = decodeSystemOneResponse(sampleSystemOneResponse, headers).get()
    check decoded.model == "jev-1.13.0"
    check decoded.requestId == "req_123"
    check decoded.usage.inputTokens == some(296)
    check decoded.noul("is_urgent").get().noul == 0.95
    check decoded.choice("department").get().choice == "billing"
    check decoded.score("frustration").get().score == 1.05

  test "decode invalid system one response":
    check decodeSystemOneResponse("not json", initTable[string, string]()).isErr
    check decodeSystemOneResponse("{}", initTable[string, string]()).isErr

  test "decode typesafe list models":
    var headers = initTable[string, string]()
    headers["x-typesafe-request-id"] = "m1"
    let decoded = decodeListModelsResponse(
      typesafeProfile, sampleModelsResponse, headers,
    ).get()
    check decoded.models.len == 1
    check decoded.models[0].name == "jev-latest"
    check decoded.models[0].description == "Latest stable Jev"
    check decoded.requestId == "m1"

  test "decode ollama list models":
    let decoded = decodeListModelsResponse(
      ollamaProfile,
      """{"models":[{"name":"nimble:latest"}]}""",
      initTable[string, string](),
    ).get()
    check decoded.models[0].name == "nimble:latest"
    check decoded.models[0].description == ""

  test "decodeJsonContent accepts object and array":
    let obj = decodeJsonContent(parseJson("""{"a":1}""")).get()
    check obj.contentKind == jckObject
    let arr = decodeJsonContent(parseJson("""[1,"x"]""")).get()
    check arr.contentKind == jckArray

suite "wire headers":
  test "mergeHeaders preserves auth from base":
    var base = initTable[string, string]()
    base["authorization"] = "Bearer secret"
    base["accept"] = "application/json"
    var extra = initTable[string, string]()
    extra["Authorization"] = "Bearer override"
    extra["X-Custom"] = "yes"
    let merged = mergeHeaders(base, extra)
    check merged["authorization"] == "Bearer secret"
    check merged["x-custom"] == "yes"

  test "joinUrl normalizes slashes":
    check joinUrl("https://api.test/", "/v1/systemone") == "https://api.test/v1/systemone"
    check joinUrl("https://api.test", "v1/models") == "https://api.test/v1/models"
