import std/[os, strutils, tables, options]
import results
import constants

type
  JevFailureKind* = enum
    jfkConfig, jfkValidation, jfkApi, jfkConnection, jfkTimeout, jfkResponse

  # Plain object so failures ride in Result without heap allocation or exceptions.
  JevFailure* = object
    failureKind*: JevFailureKind
    configMessage*: string
    validationMessage*: string
    status*: int
    body*: string
    headers*: Table[string, string]
    endpoint*: string
    connectionMessage*: string
    timeoutSec*: float
    fieldPath*: string
    responseMessage*: string

  JevError* = ref object of CatchableError
    failure*: JevFailure

  JevApiError* = ref object of JevError
    status*: int
    body*: string
    headers*: Table[string, string]
    endpoint*: string

  JevBadRequestError* = ref object of JevApiError
  JevAuthenticationError* = ref object of JevApiError
  JevPermissionDeniedError* = ref object of JevApiError
  JevNotFoundError* = ref object of JevApiError
  JevUnprocessableEntityError* = ref object of JevApiError
  JevRateLimitError* = ref object of JevApiError
    retryAfterMs*: Option[int]
  JevInternalServerError* = ref object of JevApiError

  JevConnectionError* = ref object of JevError
  JevTimeoutError* = ref object of JevError
    timeoutSec*: float
  JevResponseValidationError* = ref object of JevError
    fieldPath*: string

proc message*(f: JevFailure): string =
  case f.failureKind
  of jfkConfig: f.configMessage
  of jfkValidation: f.validationMessage
  of jfkApi: "HTTP " & $f.status & " from " & f.endpoint
  of jfkConnection: f.connectionMessage
  of jfkTimeout: "request timed out after " & $f.timeoutSec & "s"
  of jfkResponse:
    if f.fieldPath.len > 0:
      "invalid response at " & f.fieldPath & ": " & f.responseMessage
    else:
      f.responseMessage

proc configFailure*(msg: string): JevFailure =
  JevFailure(failureKind: jfkConfig, configMessage: msg)

proc validationFailure*(msg: string): JevFailure =
  JevFailure(failureKind: jfkValidation, validationMessage: msg)

proc apiFailure*(
    status: int; body, endpoint: string; headers: Table[string, string],
): JevFailure =
  JevFailure(
    failureKind: jfkApi,
    status: status,
    body: body,
    headers: headers,
    endpoint: endpoint,
  )

proc connectionFailure*(msg: string): JevFailure =
  JevFailure(failureKind: jfkConnection, connectionMessage: msg)

proc timeoutFailure*(timeoutSec: float): JevFailure =
  JevFailure(failureKind: jfkTimeout, timeoutSec: timeoutSec)

proc responseFailure*(fieldPath, msg: string): JevFailure =
  JevFailure(failureKind: jfkResponse, fieldPath: fieldPath, responseMessage: msg)

proc requestId*(f: JevFailure): Option[string] =
  if f.failureKind == jfkApi:
    let key = RequestIdHeader
    for k, v in f.headers:
      if k.toLowerAscii == key:
        return some(v)
  none(string)

proc parseRetryAfterMs*(headers: Table[string, string]): Option[int] =
  # Supports TypeSafe's retry-after-ms and standard Retry-After (seconds, numeric only).
  for k, v in headers:
    let lk = k.toLowerAscii
    if lk == "retry-after-ms":
      try:
        return some(parseInt(v))
      except ValueError:
        discard
    if lk == "retry-after":
      try:
        let sec = parseFloat(v)
        return some(int(sec * 1000.0))
      except ValueError:
        discard
  none(int)

proc raiseFailure*(f: JevFailure) {.noreturn.} =
  case f.failureKind
  of jfkConfig, jfkValidation, jfkConnection:
    raise JevError(msg: f.message(), failure: f)
  of jfkTimeout:
    raise JevTimeoutError(msg: f.message(), failure: f, timeoutSec: f.timeoutSec)
  of jfkResponse:
    raise JevResponseValidationError(
      msg: f.message(), failure: f, fieldPath: f.fieldPath,
    )
  of jfkApi:
    let retryMs = parseRetryAfterMs(f.headers)
    case f.status
    of 400:
      raise JevBadRequestError(
        msg: f.message(), failure: f, status: f.status, body: f.body,
        headers: f.headers, endpoint: f.endpoint,
      )
    of 401:
      raise JevAuthenticationError(
        msg: f.message(), failure: f, status: f.status, body: f.body,
        headers: f.headers, endpoint: f.endpoint,
      )
    of 403:
      raise JevPermissionDeniedError(
        msg: f.message(), failure: f, status: f.status, body: f.body,
        headers: f.headers, endpoint: f.endpoint,
      )
    of 404:
      raise JevNotFoundError(
        msg: f.message(), failure: f, status: f.status, body: f.body,
        headers: f.headers, endpoint: f.endpoint,
      )
    of 422:
      raise JevUnprocessableEntityError(
        msg: f.message(), failure: f, status: f.status, body: f.body,
        headers: f.headers, endpoint: f.endpoint,
      )
    of 429:
      raise JevRateLimitError(
        msg: f.message(), failure: f, status: f.status, body: f.body,
        headers: f.headers, endpoint: f.endpoint, retryAfterMs: retryMs,
      )
    else:
      raise JevInternalServerError(
        msg: f.message(), failure: f, status: f.status, body: f.body,
        headers: f.headers, endpoint: f.endpoint,
      )

proc validateApiKey*(raw: string): Result[string, JevFailure] =
  let key = raw.strip()
  if key.len == 0:
    return err(configFailure("API key is missing or empty"))
  for ch in key:
    if ord(ch) < 32 or ord(ch) == 127:
      return err(configFailure("API key contains control characters"))
    if ord(ch) > 127:
      return err(configFailure("API key contains non-ASCII characters"))
  if key.contains(' ') or key.contains('\t'):
    return err(configFailure("API key contains whitespace"))
  ok(key)

proc envOrDefault*(name, defaultValue: string): string =
  let v = getEnv(name, defaultValue)
  if v.strip().len == 0:
    defaultValue # treat whitespace-only env as unset
  else:
    v.strip()
