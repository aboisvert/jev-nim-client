import std/[unittest, tables, options]
import jev_nim_client/retry
import jev_nim_client/errors

suite "retry policy":
  test "default policy retries 408 429 and 5xx but not 401":
    var policy = defaultRetryPolicy()
    policy.backoffInitial = 0.0
    policy.backoffJitter = 0.0
    policy.totalBudgetSec = some(60.0)
    let headers = initTable[string, string]()
    check shouldRetryHttp(policy, 0, 408, headers, 0.0)[0]
    check shouldRetryHttp(policy, 0, 429, headers, 0.0)[0]
    check shouldRetryHttp(policy, 0, 503, headers, 0.0)[0]
    check not shouldRetryHttp(policy, 0, 401, headers, 0.0)[0]

  test "shouldRetryHttp respects retry-after and skips 401":
    var policy = defaultRetryPolicy()
    policy.maxRetries = 2
    policy.backoffInitial = 0.0
    policy.backoffJitter = 0.0
    policy.totalBudgetSec = some(60.0)
    var headers = initTable[string, string]()
    headers["retry-after"] = "2"
    let (retry429, delay429) = shouldRetryHttp(policy, 0, 429, headers, 0.0)
    check retry429
    check delay429 >= 2.0
    let (retry401, _) = shouldRetryHttp(policy, 0, 401, headers, 0.0)
    check not retry401

  test "retry budget stops further attempts":
    var policy = defaultRetryPolicy()
    policy.maxRetries = 5
    policy.backoffInitial = 10.0
    policy.backoffJitter = 0.0
    policy.totalBudgetSec = some(5.0)
    let headers = initTable[string, string]()
    let (retry, _) = shouldRetryHttp(policy, 0, 503, headers, 4.0)
    check not retry

  test "shouldRetryFailure retries connection errors":
    var policy = defaultRetryPolicy()
    policy.maxRetries = 1
    policy.backoffInitial = 0.0
    policy.backoffJitter = 0.0
    policy.totalBudgetSec = some(30.0)
    let failure = connectionFailure("reset")
    let (retry, _) = shouldRetryFailure(policy, 0, failure, 0.0)
    check retry

  test "shouldRetryFailure does not retry validation errors":
    var policy = defaultRetryPolicy()
    let failure = validationFailure("bad input")
    let (retry, _) = shouldRetryFailure(policy, 0, failure, 0.0)
    check not retry

  test "backoffDelaySec grows with attempt":
    var policy = defaultRetryPolicy()
    policy.backoffInitial = 1.0
    policy.backoffMax = 8.0
    policy.backoffJitter = 0.0
    check backoffDelaySec(policy, 1) == 1.0
    check backoffDelaySec(policy, 2) == 2.0
    check backoffDelaySec(policy, 3) == 4.0
    check backoffDelaySec(policy, 4) == 8.0
