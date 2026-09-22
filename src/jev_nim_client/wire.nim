import std/[json, tables, options, strutils]
import content, questions, answers, errors, constants, results_shim

proc encodeJsonValue*(v: JsonValue): JsonNode =
  case v.valueKind
  of jvkNull: newJNull()
  of jvkString: newJString(v.s)
  of jvkInt: newJInt(v.i)
  of jvkFloat: newJFloat(v.f)
  of jvkBool: newJBool(v.b)
  of jvkArray:
    var arr = newJArray()
    for item in v.arr:
      arr.add encodeJsonValue(item)
    arr
  of jvkObject:
    var obj = newJObject()
    for k, val in v.obj:
      obj[k] = encodeJsonValue(val)
    obj

proc encodeJsonContent*(c: JsonContent): JsonNode =
  case c.contentKind
  of jckString: newJString(c.text)
  of jckObject:
    var obj = newJObject()
    for k, val in c.obj:
      obj[k] = encodeJsonValue(val)
    obj
  of jckArray:
    var arr = newJArray()
    for item in c.arr:
      arr.add encodeJsonValue(item)
    arr

proc encodeState*(state: JsonContent): JsonNode =
  encodeJsonContent(state)

proc encodeState*(state: string): JsonNode =
  newJString(state)

proc encodeNoulCriteria*(c: NoulCriteria): JsonNode =
  var obj = newJObject()
  if c.trueDesc.isSome:
    obj["true"] = encodeJsonContent(c.trueDesc.get())
  if c.falseDesc.isSome:
    obj["false"] = encodeJsonContent(c.falseDesc.get())
  obj

proc encodeQuestion*(q: Question): JsonNode =
  var obj = newJObject()
  case q.questionKind
  of qkNoul:
    obj["type"] = newJString("noul")
    let n = q.noul
    if n.instructions.isSome:
      obj["instructions"] = encodeJsonContent(n.instructions.get())
    if n.criteria.isSome:
      obj["criteria"] = encodeNoulCriteria(n.criteria.get())
  of qkChoice:
    obj["type"] = newJString("choice")
    let ch = q.choice
    if ch.instructions.isSome:
      obj["instructions"] = encodeJsonContent(ch.instructions.get())
    var crit = newJObject()
    for k, v in ch.criteria:
      if v.isSome:
        crit[k] = encodeJsonContent(v.get())
      else:
        crit[k] = newJNull() # option listed without description; API still expects the key
    obj["criteria"] = crit
  of qkScore:
    obj["type"] = newJString("score")
    let sc = q.score
    if sc.instructions.isSome:
      obj["instructions"] = encodeJsonContent(sc.instructions.get())
    var levels = newJArray()
    for level in sc.criteria:
      levels.add encodeJsonContent(level)
    obj["criteria"] = levels
  obj

proc encodeSystemOneBody*(
    state: JsonContent; model: string; questions: Questions,
): JsonNode =
  var qObj = newJObject()
  for id, q in questions:
    qObj[id] = encodeQuestion(q)
  result = newJObject()
  result["state"] = encodeState(state)
  result["model"] = newJString(model)
  result["questions"] = qObj

proc encodeSystemOneBody*(
    state: string; model: string; questions: Questions,
): JsonNode =
  var qObj = newJObject()
  for id, q in questions:
    qObj[id] = encodeQuestion(q)
  result = newJObject()
  result["state"] = encodeState(state)
  result["model"] = newJString(model)
  result["questions"] = qObj

proc decodeJsonValue*(node: JsonNode): Result[JsonValue, string] =
  case node.kind
  of JNull:
    ok[JsonValue, string](jsonNull())
  of JString:
    ok[JsonValue, string](jsonStr(node.getStr()))
  of JInt:
    ok[JsonValue, string](jsonInt(node.getInt()))
  of JFloat:
    ok[JsonValue, string](jsonFloat(node.getFloat()))
  of JBool:
    ok[JsonValue, string](jsonBool(node.getBool()))
  of JArray:
    var arr = newSeq[JsonValue]()
    for item in node:
      let decoded = decodeJsonValue(item)
      if decoded.isErr:
        return err[JsonValue, string](decoded.error)
      arr.add decoded.unwrap()
    ok[JsonValue, string](jsonArr(arr))
  of JObject:
    var obj = initOrderedTable[string, JsonValue]()
    for k, v in node.pairs:
      let decoded = decodeJsonValue(v)
      if decoded.isErr:
        return err[JsonValue, string](decoded.error)
      obj[k] = decoded.unwrap()
    ok[JsonValue, string](jsonObj(obj))

proc decodeJsonContent*(node: JsonNode): Result[JsonContent, string] =
  # API allows state/instructions as a JSON string, object, or array — not only strings.
  if node.kind == JString:
    return ok[JsonContent, string](content(node.getStr()))
  if node.kind == JObject:
    var obj = initOrderedTable[string, JsonValue]()
    for k, v in node.pairs:
      let decoded = decodeJsonValue(v)
      if decoded.isErr:
        return err[JsonContent, string](decoded.error)
      obj[k] = decoded.unwrap()
    return ok[JsonContent, string](jsonContentObj(obj))
  if node.kind == JArray:
    var arr = newSeq[JsonValue]()
    for item in node:
      let decoded = decodeJsonValue(item)
      if decoded.isErr:
        return err[JsonContent, string](decoded.error)
      arr.add decoded.unwrap()
    return ok[JsonContent, string](jsonContentArr(arr))
  err[JsonContent, string]("expected string, object, or array for JsonContent")

proc headerTable*(headers: seq[(string, string)]): Table[string, string] =
  result = initTable[string, string]()
  for (k, v) in headers:
    result[k.toLowerAscii] = v

proc requestIdFromHeaders*(headers: Table[string, string]): string =
  # Correlation id is response header only (x-typesafe-request-id), not in JSON body.
  if RequestIdHeader in headers:
    headers[RequestIdHeader]
  else:
    ""

proc decodeUsage*(node: JsonNode): Usage =
  result = Usage()
  if node.kind != JObject:
    return
  if "input_tokens" in node and node["input_tokens"].kind != JNull:
    result.inputTokens = some(node["input_tokens"].getInt())
  if "output_tokens" in node and node["output_tokens"].kind != JNull:
    result.outputTokens = some(node["output_tokens"].getInt())

proc decodeAnswer*(node: JsonNode; id: string): Result[Answer, string] =
  if node.kind != JObject:
    return err[Answer, string]("answer '" & id & "' is not an object")
  if "type" notin node:
    return err[Answer, string]("answer '" & id & "' missing type")
  let typ = node["type"].getStr()
  case typ
  of "noul":
    if "noul" notin node:
      return err[Answer, string]("answer '" & id & "' missing noul field")
    ok[Answer, string](Answer(
      answerKind: akNoul, noulAns: NoulAnswer(noul: node["noul"].getFloat()),
    ))
  of "choice":
    if "choice" notin node or "probabilities" notin node or "confidence" notin node:
      return err[Answer, string]("answer '" & id & "' missing choice fields")
    var probs = initOrderedTable[string, float]()
    let pnode = node["probabilities"]
    if pnode.kind != JObject:
      return err[Answer, string]("answer '" & id & "' probabilities must be an object")
    for k, v in pnode.pairs:
      probs[k] = v.getFloat()
    ok[Answer, string](Answer(
      answerKind: akChoice,
      choiceAns: ChoiceAnswer(
        choice: node["choice"].getStr(),
        probabilities: probs,
        confidence: node["confidence"].getFloat(),
      ),
    ))
  of "score":
    if "score" notin node or "legend" notin node:
      return err[Answer, string]("answer '" & id & "' missing score fields")
    if "probabilities" notin node or "confidence" notin node:
      return err[Answer, string]("answer '" & id & "' missing score probability fields")
    var legend = initOrderedTable[string, JsonContent]()
    let lnode = node["legend"]
    if lnode.kind != JObject:
      return err[Answer, string]("answer '" & id & "' legend must be an object")
    for k, v in lnode.pairs:
      let decoded = decodeJsonContent(v)
      if decoded.isErr:
        return err[Answer, string]("answer '" & id & "' legend." & k & ": " & decoded.error)
      legend[k] = decoded.unwrap()
    var probs = initOrderedTable[string, float]()
    let pnode = node["probabilities"]
    if pnode.kind != JObject:
      return err[Answer, string]("answer '" & id & "' probabilities must be an object")
    for k, v in pnode.pairs:
      probs[k] = v.getFloat()
    ok[Answer, string](Answer(
      answerKind: akScore,
      scoreAns: ScoreAnswer(
        score: node["score"].getFloat(),
        legend: legend,
        probabilities: probs,
        confidence: node["confidence"].getFloat(),
      ),
    ))
  else:
    err[Answer, string]("answer '" & id & "' has unknown type: " & typ)

proc decodeSystemOneResponse*(
    body: string; headers: Table[string, string],
): Result[SystemOneResponse, JevFailure] =
  let node =
    try:
      parseJson(body)
    except JsonParsingError as e:
      return err[SystemOneResponse, JevFailure](responseFailure("", "invalid JSON: " & e.msg))

  if node.kind != JObject:
    return err[SystemOneResponse, JevFailure](responseFailure("", "response body must be an object"))
  if "model" notin node:
    return err[SystemOneResponse, JevFailure](responseFailure("model", "missing model field"))
  var resp = SystemOneResponse(
    model: node["model"].getStr(),
    usage: decodeUsage(if "usage" in node: node["usage"] else: newJNull()),
    requestId: requestIdFromHeaders(headers),
  )
  if "answers" notin node:
    return err[SystemOneResponse, JevFailure](responseFailure("answers", "missing answers field"))
  let ansNode = node["answers"]
  if ansNode.kind != JObject:
    return err[SystemOneResponse, JevFailure](responseFailure("answers", "answers must be an object"))
  resp.answers = initOrderedTable[string, Answer]()
  for id, ans in ansNode.pairs:
    let decoded = decodeAnswer(ans, id)
    if decoded.isErr:
      return err[SystemOneResponse, JevFailure](responseFailure("answers." & id, decoded.error))
    resp.answers[id] = decoded.unwrap()
  ok[SystemOneResponse, JevFailure](resp)

proc decodeListModelsResponse*(
    body: string; headers: Table[string, string],
): Result[ListModelsResponse, JevFailure] =
  let node =
    try:
      parseJson(body)
    except JsonParsingError as e:
      return err[ListModelsResponse, JevFailure](responseFailure("", "invalid JSON: " & e.msg))

  if node.kind != JObject:
    return err[ListModelsResponse, JevFailure](responseFailure("", "response body must be an object"))
  if "models" notin node:
    return err[ListModelsResponse, JevFailure](responseFailure("models", "missing models field"))
  let arr = node["models"]
  if arr.kind != JArray:
    return err[ListModelsResponse, JevFailure](responseFailure("models", "models must be an array"))
  var models = newSeq[ModelMetadata]()
  var i = 0
  for item in arr:
    if item.kind != JObject:
      return err[ListModelsResponse, JevFailure](responseFailure("models[" & $i & "]", "model entry must be an object"))
    if "name" notin item or "description" notin item or "release_date" notin item:
      return err[ListModelsResponse, JevFailure](responseFailure("models[" & $i & "]", "missing model metadata fields"))
    models.add ModelMetadata(
      name: item["name"].getStr(),
      description: item["description"].getStr(),
      releaseDate: item["release_date"].getStr(),
    )
    inc i
  ok[ListModelsResponse, JevFailure](ListModelsResponse(
    models: models, requestId: requestIdFromHeaders(headers),
  ))

proc mergeHeaders*(
    base: Table[string, string]; extra: Table[string, string],
): Table[string, string] =
  result = base
  for k, v in extra:
    let lk = k.toLowerAscii
    # Auth, accept, and user-agent come from buildDefaultHeaders and must not be overridden.
    if lk notin ["authorization", "accept", "user-agent"]:
      result[lk] = v
