import std/[os, tables, times]
import errors, retry, results_shim

type
  RawResponse* = object
    status*: int
    body*: string
    headers*: Table[string, string]

  # One HTTP round-trip; sync and async clients plug in different implementations.
  RequestExecutor* = proc(
    verb, url, body: string; headers: Table[string, string]; timeoutSec: float,
  ): Result[RawResponse, JevFailure] {.gcsafe.}

  SleepProc* = proc(seconds: float) {.gcsafe.}
  # Injected so async client can waitFor sleepAsync without blocking the sync sleep().

proc defaultSleep*(seconds: float) =
  sleep(int(seconds * 1000.0))

proc classifyHttpResponse*(
    resp: RawResponse; endpoint: string,
): Result[RawResponse, JevFailure] =
  if resp.status >= 200 and resp.status < 300:
    ok[RawResponse, JevFailure](resp)
  else:
    # Transport succeeded; HTTP status errors become JevFailure and may be retried upstream.
    err[RawResponse, JevFailure](apiFailure(resp.status, resp.body, endpoint, resp.headers))

proc executeWithRetry*(
    policy: RetryPolicy;
    executor: RequestExecutor;
    sleepProc: SleepProc;
    verb, url, body: string;
    headers: Table[string, string];
    timeoutSec: float;
    endpoint: string;
): Result[RawResponse, JevFailure] =
  var attempt = 0
  let start = epochTime()
  while true:
    let execResult = executor(verb, url, body, headers, timeoutSec)
    if execResult.isErr:
      let failure = execResult.error
      let elapsed = epochTime() - start
      let (retry, delay) = shouldRetryFailure(policy, attempt, failure, elapsed)
      if not retry:
        return err[RawResponse, JevFailure](failure)
      sleepProc(delay)
      inc attempt
      continue

    let resp = execResult.unwrap()
    let classified = classifyHttpResponse(resp, endpoint)
    if classified.isOk:
      return classified

    # Same retry path as connection/timeout failures once status is mapped to JevFailure.
    let failure = classified.error
    let elapsed = epochTime() - start
    let (retry, delay) = shouldRetryFailure(policy, attempt, failure, elapsed)
    if not retry:
      return err[RawResponse, JevFailure](failure)
    sleepProc(delay)
    inc attempt
