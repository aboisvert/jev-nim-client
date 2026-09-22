import std/[random, sets, tables, options]
import errors

type
  RetryPolicy* = object
    maxRetries*: int
    backoffInitial*: float
    backoffMax*: float
    backoffJitter*: float
    httpStatuses*: HashSet[int]
    respectRetryAfter*: bool
    retryConnection*: bool
    retryTimeout*: bool
    totalBudgetSec*: Option[float]

proc defaultRetryHttpStatuses*(): HashSet[int] =
  result = initHashSet[int]()
  result.incl 408
  result.incl 429
  for code in 500 .. 599:
    result.incl code

proc defaultRetryPolicy*(): RetryPolicy =
  RetryPolicy(
    maxRetries: 2,
    backoffInitial: 0.5,
    backoffMax: 5.0,
    backoffJitter: 0.25,
    httpStatuses: defaultRetryHttpStatuses(),
    respectRetryAfter: true,
    retryConnection: true,
    retryTimeout: true,
    totalBudgetSec: some(30.0),
  )

proc backoffDelaySec*(policy: RetryPolicy; attempt: int): float =
  if policy.backoffInitial <= 0.0:
    return 0.0
  var delay = policy.backoffInitial
  for _ in 1 ..< attempt:
    delay = min(delay * 2.0, policy.backoffMax)
  if policy.backoffJitter > 0.0:
    let jitter = rand(0.0 .. policy.backoffJitter * delay)
    delay = max(0.0, delay - jitter)
  delay

proc shouldRetryHttp*(
    policy: RetryPolicy; attempt: int; status: int; headers: Table[string, string];
    elapsedSec: float,
): (bool, float) =
  if attempt >= policy.maxRetries:
    return (false, 0.0)
  if status notin policy.httpStatuses:
    return (false, 0.0)
  var delay = backoffDelaySec(policy, attempt + 1)
  if policy.respectRetryAfter:
    let ra = parseRetryAfterMs(headers)
    if ra.isSome:
      delay = max(delay, ra.get().float / 1000.0)
  if policy.totalBudgetSec.isSome:
    if elapsedSec + delay >= policy.totalBudgetSec.get():
      return (false, 0.0)
  (true, delay)

proc shouldRetryFailure*(
    policy: RetryPolicy; attempt: int; failure: JevFailure; elapsedSec: float,
): (bool, float) =
  if attempt >= policy.maxRetries:
    return (false, 0.0)
  case failure.failureKind
  of jfkApi:
    return shouldRetryHttp(
      policy, attempt, failure.status, failure.headers, elapsedSec,
    )
  of jfkConnection:
    if not policy.retryConnection:
      return (false, 0.0)
  of jfkTimeout:
    if not policy.retryTimeout:
      return (false, 0.0)
  else:
    return (false, 0.0)
  var delay = backoffDelaySec(policy, attempt + 1)
  if policy.totalBudgetSec.isSome:
    if elapsedSec + delay >= policy.totalBudgetSec.get():
      return (false, 0.0)
  (true, delay)
