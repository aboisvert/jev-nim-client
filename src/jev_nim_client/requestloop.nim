import std/[asyncdispatch, os, tables, times]
import errors, retry, results

type
  RawResponse* = object
    status*: int
    body*: string
    headers*: Table[string, string]

  SyncRequestExecutor* = proc(
    verb, url, body: string; headers: Table[string, string]; timeoutSec: float,
  ): Result[RawResponse, JevFailure] {.gcsafe.}

  AsyncRequestExecutor* = proc(
    verb, url, body: string; headers: Table[string, string]; timeoutSec: float,
  ): Future[Result[RawResponse, JevFailure]] {.gcsafe, async.}

  SleepProc* = proc(seconds: float) {.gcsafe.}

proc defaultSleep*(seconds: float) =
  sleep(int(seconds * 1000.0))

proc classifyHttpResponse*(
    resp: RawResponse; endpoint: string,
): Result[RawResponse, JevFailure] =
  if resp.status >= 200 and resp.status < 300:
    ok(resp)
  else:
    err(apiFailure(resp.status, resp.body, endpoint, resp.headers))

template retryHttpLoop(
    policy: RetryPolicy;
    endpoint: string;
    execCall: untyped;
    sleepProc: SleepProc,
): untyped =
  var attempt = 0
  let start = epochTime()
  while true:
    let execResult = execCall
    if execResult.isErr:
      let failure = execResult.unsafeError
      let elapsed = epochTime() - start
      let (retry, delay) = shouldRetryFailure(policy, attempt, failure, elapsed)
      if not retry:
        return Result[RawResponse, JevFailure].err(failure)
      sleepProc(delay)
      inc attempt
      continue

    let resp = execResult.get()
    let classified = classifyHttpResponse(resp, endpoint)
    if classified.isOk:
      return classified

    let failure = classified.unsafeError
    let elapsed = epochTime() - start
    let (retry, delay) = shouldRetryFailure(policy, attempt, failure, elapsed)
    if not retry:
      return Result[RawResponse, JevFailure].err(failure)
    sleepProc(delay)
    inc attempt

proc executeWithRetry*(
    policy: RetryPolicy;
    executor: SyncRequestExecutor;
    sleepProc: SleepProc;
    verb, url, body: string;
    headers: Table[string, string];
    timeoutSec: float;
    endpoint: string;
): Result[RawResponse, JevFailure] =
  retryHttpLoop(
    policy,
    endpoint,
    executor(verb, url, body, headers, timeoutSec),
    sleepProc,
  )

proc executeWithRetryAsync*(
    policy: RetryPolicy;
    executor: AsyncRequestExecutor;
    verb, url, body: string;
    headers: Table[string, string];
    timeoutSec: float;
    endpoint: string;
): Future[Result[RawResponse, JevFailure]] {.async.} =
  var attempt = 0
  let start = epochTime()
  while true:
    let execResult = await executor(verb, url, body, headers, timeoutSec)
    if execResult.isErr:
      let failure = execResult.unsafeError
      let elapsed = epochTime() - start
      let (retry, delay) = shouldRetryFailure(policy, attempt, failure, elapsed)
      if not retry:
        return Result[RawResponse, JevFailure].err(failure)
      await sleepAsync(int(delay * 1000.0))
      inc attempt
      continue

    let resp = execResult.get()
    let classified = classifyHttpResponse(resp, endpoint)
    if classified.isOk:
      return classified

    let failure = classified.unsafeError
    let elapsed = epochTime() - start
    let (retry, delay) = shouldRetryFailure(policy, attempt, failure, elapsed)
    if not retry:
      return Result[RawResponse, JevFailure].err(failure)
    await sleepAsync(int(delay * 1000.0))
    inc attempt
