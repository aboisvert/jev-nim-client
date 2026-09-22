import std/[asyncdispatch, httpclient, os, tables, options, strutils, json]
import constants, content, questions, answers, errors, retry, wire, requestloop, syncclient, results_shim

export content, questions, answers, errors, retry
export syncclient.RequestOptions, syncclient.defaultRequestOptions
export requestloop.AsyncRequestExecutor

type
  AsyncJevClient* = ref object
    apiKey: string
    baseUrl: string
    defaultModel: string
    timeoutSec: float
    retryPolicy: RetryPolicy
    defaultHeaders: Table[string, string]
    httpClient: AsyncHttpClient
    executor: AsyncRequestExecutor
    ownsHttpClient: bool # see syncclient.JevClient.ownsHttpClient

proc makeAsyncExecutor(client: AsyncHttpClient): AsyncRequestExecutor =
  proc execute(
      verb, url, body: string; headers: Table[string, string]; timeoutSec: float,
  ): Future[Result[RawResponse, JevFailure]] {.async.} =
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
          HttpPost
      let resp = await client.request(url, httpMethod, body, reqHeaders)
      let respBody = await resp.body
      var hdrs = initTable[string, string]()
      for k, v in resp.headers:
        hdrs[k.toLowerAscii] = v
      ok[RawResponse, JevFailure](RawResponse(
        status: ord(resp.code), body: respBody, headers: hdrs,
      ))
    except CatchableError as e:
      if "timeout" in e.msg.toLowerAscii():
        err[RawResponse, JevFailure](timeoutFailure(timeoutSec))
      else:
        err[RawResponse, JevFailure](connectionFailure(e.msg))
  execute

proc newAsyncJevClient*(
    apiKey = "";
    baseUrl = "";
    defaultModel = "";
    timeoutSec = DefaultTimeoutSec;
    retryPolicy = defaultRetryPolicy();
    extraHeaders = initTable[string, string]();
    executor: Option[AsyncRequestExecutor] = none(AsyncRequestExecutor),
    httpClient: Option[AsyncHttpClient] = none(AsyncHttpClient),
): Result[AsyncJevClient, JevFailure] =
  let rawKey =
    if apiKey.len > 0:
      apiKey
    else:
      getEnv(ApiKeyEnv, "")
  let keyResult = validateApiKey(rawKey)
  if keyResult.isErr:
    return err[AsyncJevClient, JevFailure](keyResult.error)
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

  var client = AsyncJevClient(
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
    client.httpClient = newAsyncHttpClient()
  if executor.isSome:
    client.executor = executor.get()
  else:
    client.executor = makeAsyncExecutor(client.httpClient)
  ok[AsyncJevClient, JevFailure](client)

proc newAsyncJevClientOrRaise*(
    apiKey = "";
    baseUrl = "";
    defaultModel = "";
    timeoutSec = DefaultTimeoutSec;
    retryPolicy = defaultRetryPolicy();
    extraHeaders = initTable[string, string]();
    executor: Option[AsyncRequestExecutor] = none(AsyncRequestExecutor),
    httpClient: Option[AsyncHttpClient] = none(AsyncHttpClient),
): AsyncJevClient =
  newAsyncJevClient(
    apiKey, baseUrl, defaultModel, timeoutSec, retryPolicy, extraHeaders, executor,
    httpClient,
  ).valueOr:
    raiseFailure(failure)

proc close*(client: AsyncJevClient) =
  if client.isNil:
    return
  if client.ownsHttpClient:
    client.httpClient.close()

proc resolveAsyncOptions(
    client: AsyncJevClient; options: RequestOptions,
): (string, float, RetryPolicy, Table[string, string]) =
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

proc sendAsyncRequest(
    client: AsyncJevClient;
    verb, path: string;
    body: string;
    options: RequestOptions,
): Future[Result[RawResponse, JevFailure]] {.async.} =
  let (model, timeout, retry, headers) = resolveAsyncOptions(client, options)
  discard model
  let url = joinUrl(client.baseUrl, path)
  let endpoint = verb & " " & url
  await executeWithRetryAsync(
    retry,
    client.executor,
    verb,
    url,
    body,
    headers,
    timeout,
    endpoint,
  )

proc systemOne*(
    client: AsyncJevClient;
    state: JsonContent;
    questions: Questions;
    options = defaultRequestOptions(),
): Future[Result[SystemOneResponse, JevFailure]] {.async.} =
  let validated = validateQuestions(questions)
  if validated.isErr:
    return err[SystemOneResponse, JevFailure](validationFailure(validated.error))
  let (model, _, _, _) = resolveAsyncOptions(client, options)
  let payload = encodeSystemOneBody(state, model, questions)
  let respResult = await sendAsyncRequest(client, "POST", SystemOnePath, $payload, options)
  if respResult.isErr:
    return err[SystemOneResponse, JevFailure](respResult.error)
  let httpResp = respResult.unwrap()
  decodeSystemOneResponse(httpResp.body, httpResp.headers)

proc systemOne*(
    client: AsyncJevClient;
    state: string;
    questions: Questions;
    options = defaultRequestOptions(),
): Future[Result[SystemOneResponse, JevFailure]] {.async.} =
  await systemOne(client, content(state), questions, options)

proc systemOneOrRaise*(
    client: AsyncJevClient;
    state: JsonContent;
    questions: Questions;
    options = defaultRequestOptions(),
): Future[SystemOneResponse] {.async.} =
  (await systemOne(client, state, questions, options)).valueOr:
    raiseFailure(failure)

proc systemOneOrRaise*(
    client: AsyncJevClient;
    state: string;
    questions: Questions;
    options = defaultRequestOptions(),
): Future[SystemOneResponse] {.async.} =
  await systemOneOrRaise(client, content(state), questions, options)

proc listModels*(
    client: AsyncJevClient; options = defaultRequestOptions(),
): Future[Result[ListModelsResponse, JevFailure]] {.async.} =
  let respResult = await sendAsyncRequest(client, "GET", ModelsPath, "", options)
  if respResult.isErr:
    return err[ListModelsResponse, JevFailure](respResult.error)
  let httpResp = respResult.unwrap()
  decodeListModelsResponse(httpResp.body, httpResp.headers)

proc listModelsOrRaise*(
    client: AsyncJevClient; options = defaultRequestOptions(),
): Future[ListModelsResponse] {.async.} =
  (await listModels(client, options)).valueOr:
    raiseFailure(failure)
