import std/[json, tables, options, strutils]
import content, questions, answers, errors, constants, provider, results

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

proc encodeJsonContentForCriteria*(
    limits: ProviderLimits; c: JsonContent,
): JsonNode =
  if limits.stringCriteriaOnly:
    if c.contentKind != jckString:
      raise ValueError.newException("criteria must be strings for this provider")
    newJString(c.text)
  else:
    encodeJsonContent(c)

proc encodeNoulCriteria*(
    limits: ProviderLimits; c: NoulCriteria,
): JsonNode =
  var obj = newJObject()
  if c.trueDesc.isSome:
    obj["true"] = encodeJsonContentForCriteria(limits, c.trueDesc.get())
  if c.falseDesc.isSome:
    obj["false"] = encodeJsonContentForCriteria(limits, c.falseDesc.get())
  obj

proc encodeQuestion*(profile: ProviderProfile; q: Question): JsonNode =
  let limits = profile.limits()
  var obj = newJObject()
  case q.questionKind
  of qkNoul:
    obj["type"] = newJString("noul")
    let n = q.noul
    if n.instructions.isSome:
      obj["instructions"] = encodeJsonContent(n.instructions.get())
    if n.criteria.isSome:
      obj["criteria"] = encodeNoulCriteria(limits, n.criteria.get())
  of qkChoice:
    obj["type"] = newJString("choice")
    let ch = q.choice
    if ch.instructions.isSome:
      obj["instructions"] = encodeJsonContent(ch.instructions.get())
    var crit = newJObject()
    for k, v in ch.criteria:
      if v.isSome:
        crit[k] = encodeJsonContentForCriteria(limits, v.get())
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
      levels.add encodeJsonContentForCriteria(limits, level)
    obj["criteria"] = levels
  obj

proc validateInstructions*(
    limits: ProviderLimits; id: string; instructions: Option[JsonContent],
): Result[void, string] =
  if not limits.requiresNonemptyInstructions:
    return ok()
  if instructions.isNone:
    return err("question '" & id & "' must include instructions")
  let instr = instructions.get()
  if instr.contentKind == jckString and instr.text.strip.len == 0:
    return err("question '" & id & "' instructions must not be blank")
  ok()

proc validateOllamaCriteria*(
    limits: ProviderLimits; id: string; c: JsonContent; field: string,
): Result[void, string] =
  if not limits.stringCriteriaOnly:
    return ok()
  if c.contentKind != jckString:
    return err("question '" & id & "' " & field & " criteria must be strings for Ollama")
  ok()

proc validateQuestionCriteria*(
    profile: ProviderProfile; id: string; q: Question,
): Result[void, string] =
  let limits = profile.limits()
  case q.questionKind
  of qkNoul:
    ?validateInstructions(limits, id, q.noul.instructions)
    if q.noul.criteria.isSome:
      let c = q.noul.criteria.get
      if c.trueDesc.isSome:
        ?validateOllamaCriteria(limits, id, c.trueDesc.get, "noul true")
      if c.falseDesc.isSome:
        ?validateOllamaCriteria(limits, id, c.falseDesc.get, "noul false")
  of qkChoice:
    ?validateInstructions(limits, id, q.choice.instructions)
    for _, desc in q.choice.criteria:
      if desc.isSome:
        ?validateOllamaCriteria(limits, id, desc.get, "choice")
  of qkScore:
    ?validateInstructions(limits, id, q.score.instructions)
    for level in q.score.criteria:
      ?validateOllamaCriteria(limits, id, level, "score")
  ok()

proc validateState*(
    profile: ProviderProfile; state: JsonContent,
): Result[void, string] =
  let limits = profile.limits()
  if limits.requiresNonemptyStringState:
    if state.contentKind == jckString and state.text.strip.len == 0:
      return err("state must be nonempty")
  ok()

proc validateQuestions*(
    profile: ProviderProfile; questions: Questions,
): Result[void, string] =
  let limits = profile.limits()
  if questions.len == 0:
    return err("questions must not be empty")
  if questions.len > limits.maxQuestions:
    return err("too many questions (max " & $limits.maxQuestions & ")")
  for id, q in questions:
    if id.strip.len == 0:
      return err("question id must not be blank")
    case q.questionKind
    of qkChoice:
      let n = q.choice.criteria.len
      if n < limits.minChoiceOptions:
        return err("choice question '" & id & "' must have at least " &
          $limits.minChoiceOptions & " options")
      if n > limits.maxChoiceOptions:
        return err("choice question '" & id & "' exceeds " & $limits.maxChoiceOptions &
          " options")
    of qkScore:
      let n = q.score.criteria.len
      if n < limits.minScoreLevels:
        return err("score question '" & id & "' must have at least " &
          $limits.minScoreLevels & " levels")
      if n > limits.maxScoreLevels:
        return err("score question '" & id & "' exceeds " & $limits.maxScoreLevels & " levels")
    of qkNoul:
      discard
    ?validateQuestionCriteria(profile, id, q)
  ok()

proc encodeSystemOneBody*(
    profile: ProviderProfile;
    state: JsonContent;
    model: string;
    questions: Questions;
    keepAlive: Option[KeepAlive] = none(KeepAlive),
): Result[JsonNode, JevFailure] =
  let stateValid = validateState(profile, state)
  if stateValid.isErr:
    return err(validationFailure(stateValid.unsafeError))
  let qValid = validateQuestions(profile, questions)
  if qValid.isErr:
    return err(validationFailure(qValid.unsafeError))
  if keepAlive.isSome and not profile.limits().supportsKeepAlive:
    return err(validationFailure("keep_alive is only supported for Ollama"))
  var qObj = newJObject()
  for id, q in questions:
    qObj[id] = encodeQuestion(profile, q)
  var bodyNode = newJObject()
  bodyNode["state"] = encodeState(state)
  bodyNode["model"] = newJString(model)
  bodyNode["questions"] = qObj
  if keepAlive.isSome:
    let ka = keepAlive.get()
    case ka.kind
    of kakDuration:
      bodyNode["keep_alive"] = newJString(ka.duration)
    of kakSeconds:
      bodyNode["keep_alive"] = newJFloat(ka.seconds)
  let maxBytes = profile.limits().maxBodyBytes
  if maxBytes > 0 and ($bodyNode).len > maxBytes:
    return err(validationFailure("request body exceeds " & $maxBytes & " bytes"))
  ok(bodyNode)

proc encodeSystemOneBody*(
    profile: ProviderProfile;
    state: string;
    model: string;
    questions: Questions;
    keepAlive: Option[KeepAlive] = none(KeepAlive),
): Result[JsonNode, JevFailure] =
  encodeSystemOneBody(profile, content(state), model, questions, keepAlive)

proc decodeJsonValue*(node: JsonNode): Result[JsonValue, string] =
  case node.kind
  of JNull:
    ok(jsonNull())
  of JString:
    ok(jsonStr(node.getStr()))
  of JInt:
    ok(jsonInt(node.getInt()))
  of JFloat:
    ok(jsonFloat(node.getFloat()))
  of JBool:
    ok(jsonBool(node.getBool()))
  of JArray:
    var arr = newSeq[JsonValue]()
    for item in node:
      arr.add ?decodeJsonValue(item)
    ok(jsonArr(arr))
  of JObject:
    var obj = initOrderedTable[string, JsonValue]()
    for k, v in node.pairs:
      obj[k] = ?decodeJsonValue(v)
    ok(jsonObj(obj))

proc decodeJsonContent*(node: JsonNode): Result[JsonContent, string] =
  # API allows state/instructions as a JSON string, object, or array — not only strings.
  if node.kind == JString:
    return ok(content(node.getStr()))
  if node.kind == JObject:
    var obj = initOrderedTable[string, JsonValue]()
    for k, v in node.pairs:
      obj[k] = ?decodeJsonValue(v)
    return ok(jsonContentObj(obj))
  if node.kind == JArray:
    var arr = newSeq[JsonValue]()
    for item in node:
      arr.add ?decodeJsonValue(item)
    return ok(jsonContentArr(arr))
  err("expected string, object, or array for JsonContent")

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
    return err("answer '" & id & "' is not an object")
  if "type" notin node:
    return err("answer '" & id & "' missing type")
  let typ = node["type"].getStr()
  case typ
  of "noul":
    if "noul" notin node:
      return err("answer '" & id & "' missing noul field")
    ok(Answer(
      answerKind: akNoul, noulAns: NoulAnswer(noul: node["noul"].getFloat()),
    ))
  of "choice":
    if "choice" notin node or "probabilities" notin node or "confidence" notin node:
      return err("answer '" & id & "' missing choice fields")
    var probs = initOrderedTable[string, float]()
    let pnode = node["probabilities"]
    if pnode.kind != JObject:
      return err("answer '" & id & "' probabilities must be an object")
    for k, v in pnode.pairs:
      probs[k] = v.getFloat()
    ok(Answer(
      answerKind: akChoice,
      choiceAns: ChoiceAnswer(
        choice: node["choice"].getStr(),
        probabilities: probs,
        confidence: node["confidence"].getFloat(),
      ),
    ))
  of "score":
    if "score" notin node or "legend" notin node:
      return err("answer '" & id & "' missing score fields")
    if "probabilities" notin node or "confidence" notin node:
      return err("answer '" & id & "' missing score probability fields")
    var legend = initOrderedTable[string, JsonContent]()
    let lnode = node["legend"]
    if lnode.kind != JObject:
      return err("answer '" & id & "' legend must be an object")
    for k, v in lnode.pairs:
      let decoded = decodeJsonContent(v)
      if decoded.isErr:
        return err("answer '" & id & "' legend." & k & ": " & decoded.unsafeError)
      legend[k] = decoded.get()
    var probs = initOrderedTable[string, float]()
    let pnode = node["probabilities"]
    if pnode.kind != JObject:
      return err("answer '" & id & "' probabilities must be an object")
    for k, v in pnode.pairs:
      probs[k] = v.getFloat()
    ok(Answer(
      answerKind: akScore,
      scoreAns: ScoreAnswer(
        score: node["score"].getFloat(),
        legend: legend,
        probabilities: probs,
        confidence: node["confidence"].getFloat(),
      ),
    ))
  else:
    err("answer '" & id & "' has unknown type: " & typ)

proc decodeSystemOneResponse*(
    body: string; headers: Table[string, string],
): Result[SystemOneResponse, JevFailure] =
  let node =
    try:
      parseJson(body)
    except JsonParsingError as e:
      return err(responseFailure("", "invalid JSON: " & e.msg))

  if node.kind != JObject:
    return err(responseFailure("", "response body must be an object"))
  if "model" notin node:
    return err(responseFailure("model", "missing model field"))
  var resp = SystemOneResponse(
    model: node["model"].getStr(),
    usage: decodeUsage(if "usage" in node: node["usage"] else: newJNull()),
    requestId: requestIdFromHeaders(headers),
  )
  if "answers" notin node:
    return err(responseFailure("answers", "missing answers field"))
  let ansNode = node["answers"]
  if ansNode.kind != JObject:
    return err(responseFailure("answers", "answers must be an object"))
  resp.answers = initOrderedTable[string, Answer]()
  for id, ans in ansNode.pairs:
    let decoded = decodeAnswer(ans, id)
    if decoded.isErr:
      return err(responseFailure("answers." & id, decoded.unsafeError))
    resp.answers[id] = decoded.get()
  ok(resp)

proc decodeListModelsResponse*(
    profile: ProviderProfile;
    body: string;
    headers: Table[string, string],
): Result[ListModelsResponse, JevFailure] =
  let node =
    try:
      parseJson(body)
    except JsonParsingError as e:
      return err(responseFailure("", "invalid JSON: " & e.msg))

  if node.kind != JObject:
    return err(responseFailure("", "response body must be an object"))
  if "models" notin node:
    return err(responseFailure("models", "missing models field"))
  let arr = node["models"]
  if arr.kind != JArray:
    return err(responseFailure("models", "models must be an array"))
  var models = newSeq[ModelMetadata]()
  var i = 0
  for item in arr:
    if item.kind != JObject:
      return err(responseFailure("models[" & $i & "]", "model entry must be an object"))
    if "name" notin item:
      return err(responseFailure("models[" & $i & "]", "missing model name"))
    case profile.kind
    of typesafeAi:
      if "description" notin item or "release_date" notin item:
        return err(responseFailure("models[" & $i & "]", "missing model metadata fields"))
      models.add ModelMetadata(
        name: item["name"].getStr(),
        description: item["description"].getStr(),
        releaseDate: item["release_date"].getStr(),
      )
    of ollama:
      models.add ModelMetadata(
        name: item["name"].getStr(),
        description: "",
        releaseDate: "",
      )
    inc i
  ok(ListModelsResponse(
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
