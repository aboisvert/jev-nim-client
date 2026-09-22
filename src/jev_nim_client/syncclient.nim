import std/[httpclient, os, tables, options, strutils, json]
import constants, content, questions, answers, errors, retry, wire, requestloop, results_shim

export content, questions, answers, errors, retry, results_shim
export requestloop.SyncRequestExecutor

type
  RequestOptions* = object
    model*: Option[string]
    timeoutSec*: Option[float]
    retry*: Option[RetryPolicy]
    extraHeaders*: Table[string, string]

  JevClient* = ref object
    apiKey: string
    baseUrl: string
    defaultModel: string
    timeoutSec: float
    retryPolicy: RetryPolicy
    defaultHeaders: Table[string, string]
    httpClient: HttpClient
    executor: SyncRequestExecutor
    # False when caller passed httpClient; close() must not destroy a shared instance.
    ownsHttpClient: bool

proc defaultRequestOptions*(): RequestOptions =
  RequestOptions(
    model: none(string),
    timeoutSec: none(float),
    retry: none(RetryPolicy),
    extraHeaders: initTable[string, string](),
  )

proc buildDefaultHeaders*(apiKey: string): Table[string, string] =
  result = initTable[string, string]()
  result["authorization"] = "Bearer " & apiKey
  result["accept"] = "application/json"
  result["content-type"] = "application/json"
  result["user-agent"] = UserAgentPrefix & "/" & ClientVersion

proc makeSyncExecutor(client: HttpClient): SyncRequestExecutor =
  proc execute(
      verb, url, body: string; headers: Table[string, string]; timeoutSec: float,
  ): Result[RawResponse, JevFailure] {.gcsafe.} =
    client.timeout = int(timeoutSec * 1000.0)
    try:
      var reqHeaders = newHttpHeaders()
      for k, v in headers:
        reqHeaders.add(k, v)
      let httpMethod =
        if verb == "GET":
          HttpGet
        elif verb == "POST":
          HttpPost
        else:
          HttpPost # only GET/POST are used today; unknown verbs fall back to POST
      let resp = client.request(url, httpMethod, body, reqHeaders)
      var hdrs = initTable[string, string]()
      for k, v in resp.headers:
        hdrs[k.toLowerAscii] = v # matches wire/errors header lookup (case-insensitive)
      ok[RawResponse, JevFailure](RawResponse(
        status: ord(resp.code), body: resp.body, headers: hdrs,
      ))
    except CatchableError as e:
      # std/httpclient has no distinct timeout exception type; message is the signal.
      if "timeout" in e.msg.toLowerAscii():
        err[RawResponse, JevFailure](timeoutFailure(timeoutSec))
      else:
        err[RawResponse, JevFailure](connectionFailure(e.msg))
  execute

proc joinUrl*(baseUrl, path: string): string =
  var base = baseUrl
  while base.len > 0 and base[^1] in {'/'}:
    base.setLen(base.len - 1)
  if path.len == 0:
    base
  elif path[0] == '/':
    base & path
  else:
    base & "/" & path

proc newJevClient*(
    apiKey = "";
    baseUrl = "";
    defaultModel = "";
    timeoutSec = DefaultTimeoutSec;
    retryPolicy = defaultRetryPolicy();
    extraHeaders = initTable[string, string]();
    executor: Option[SyncRequestExecutor] = none(SyncRequestExecutor),
    httpClient: Option[HttpClient] = none(HttpClient),
): Result[JevClient, JevFailure] =
  let rawKey =
    if apiKey.len > 0:
      apiKey
    else:
      getEnv(ApiKeyEnv, "") # empty arg means "read TYPESAFE_API_KEY"
  let keyResult = validateApiKey(rawKey)
  if keyResult.isErr:
    return err[JevClient, JevFailure](keyResult.error)
  let resolvedBase =
    if baseUrl.len > 0:
      baseUrl.strip()
    else:
      envOrDefault(BaseUrlEnv, DefaultBaseUrl)
  let resolvedModel =
    if defaultModel.len > 0:
      defaultModel.strip()
    else:
      envOrDefault(DefaultModelEnv, DefaultModel)

  var client = JevClient(
    apiKey: keyResult.unwrap(),
    baseUrl: resolvedBase,
    defaultModel: resolvedModel,
    timeoutSec: timeoutSec,
    retryPolicy: retryPolicy,
    defaultHeaders: mergeHeaders(buildDefaultHeaders(keyResult.unwrap()), extraHeaders),
    ownsHttpClient: httpClient.isNone,
  )
  if httpClient.isSome:
    client.httpClient = httpClient.get()
  else:
    client.httpClient = newHttpClient()
  if executor.isSome:
    client.executor = executor.get() # stub transport in tests without touching the network
  else:
    client.executor = makeSyncExecutor(client.httpClient)
  ok[JevClient, JevFailure](client)

proc newJevClientOrRaise*(
    apiKey = "";
    baseUrl = "";
    defaultModel = "";
    timeoutSec = DefaultTimeoutSec;
    retryPolicy = defaultRetryPolicy();
    extraHeaders = initTable[string, string]();
    executor: Option[SyncRequestExecutor] = none(SyncRequestExecutor),
    httpClient: Option[HttpClient] = none(HttpClient),
): JevClient =
  newJevClient(
    apiKey, baseUrl, defaultModel, timeoutSec, retryPolicy, extraHeaders, executor,
    httpClient,
  ).valueOr:
    raiseFailure(failure)

proc close*(client: JevClient) =
  if client.isNil:
    return
  if client.ownsHttpClient:
    client.httpClient.close()

proc resolveOptions(
    client: JevClient; options: RequestOptions,
): (string, float, RetryPolicy, Table[string, string]) =
  # Per-request fields override client defaults when the corresponding Option is set.
  let model =
    if options.model.isSome:
      options.model.get()
    else:
      client.defaultModel
  let timeout =
    if options.timeoutSec.isSome:
      options.timeoutSec.get()
    else:
      client.timeoutSec
  let retry =
    if options.retry.isSome:
      options.retry.get()
    else:
      client.retryPolicy
  let headers = mergeHeaders(client.defaultHeaders, options.extraHeaders)
  (model, timeout, retry, headers)

proc sendRequest(
    client: JevClient;
    verb, path: string;
    body: string;
    options: RequestOptions,
): Result[RawResponse, JevFailure] =
  let (model, timeout, retry, headers) = resolveOptions(client, options)
  discard model # transport layer; model is only embedded in systemOne JSON by the caller
  let url = joinUrl(client.baseUrl, path)
  let endpoint = verb & " " & url # stored on API failures for debugging (not sent on the wire)
  executeWithRetry(
    retry,
    client.executor,
    defaultSleep,
    verb,
    url,
    body,
    headers,
    timeout,
    endpoint,
  )

proc systemOne*(
    client: JevClient;
    state: JsonContent;
    questions: Questions;
    options = defaultRequestOptions(),
): Result[SystemOneResponse, JevFailure] =
  let validated = validateQuestions(questions)
  if validated.isErr:
    return err[SystemOneResponse, JevFailure](validationFailure(validated.error))
  # Model comes from options here; sendRequest only handles HTTP + retry.
  let (model, _, _, _) = resolveOptions(client, options)
  let payload = encodeSystemOneBody(state, model, questions)
  let respResult = sendRequest(client, "POST", SystemOnePath, $payload, options)
  if respResult.isErr:
    return err[SystemOneResponse, JevFailure](respResult.error)
  let httpResp = respResult.unwrap()
  decodeSystemOneResponse(httpResp.body, httpResp.headers)

proc systemOne*(
    client: JevClient;
    state: string;
    questions: Questions;
    options = defaultRequestOptions(),
): Result[SystemOneResponse, JevFailure] =
  systemOne(client, content(state), questions, options)

proc systemOneOrRaise*(
    client: JevClient;
    state: JsonContent;
    questions: Questions;
    options = defaultRequestOptions(),
): SystemOneResponse =
  systemOne(client, state, questions, options).valueOr:
    raiseFailure(failure)

proc systemOneOrRaise*(
    client: JevClient;
    state: string;
    questions: Questions;
    options = defaultRequestOptions(),
): SystemOneResponse =
  systemOneOrRaise(client, content(state), questions, options)

proc listModels*(
    client: JevClient; options = defaultRequestOptions(),
): Result[ListModelsResponse, JevFailure] =
  let respResult = sendRequest(client, "GET", ModelsPath, "", options)
  if respResult.isErr:
    return err[ListModelsResponse, JevFailure](respResult.error)
  let httpResp = respResult.unwrap()
  decodeListModelsResponse(httpResp.body, httpResp.headers)

proc listModelsOrRaise*(
    client: JevClient; options = defaultRequestOptions(),
): ListModelsResponse =
  listModels(client, options).valueOr:
    raiseFailure(failure)
