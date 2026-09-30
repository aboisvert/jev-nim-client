## Live System One against TypeSafe (requires network and TYPESAFE_API_KEY).
##
## Run: JEV_RUN_E2E=1 TYPESAFE_API_KEY=ts_... nimble e2e
## Or:  just e2e-typesafe

import std/[unittest, options, os]
import results
import jev_nim_client
import e2e_support

suite "e2e typesafe":
  test "systemOne against TypeSafe Jev API":
    if not e2eEnabled():
      echo "[skip] set JEV_RUN_E2E=1 to run live tests"
      skip()
    if getEnv("TYPESAFE_API_KEY", "").len == 0:
      echo "[skip] TYPESAFE_API_KEY not set"
      skip()

    let client = newJevClient(provider = typesafeAi).get()
    defer:
      client.close()

    var opts = defaultRequestOptions()
    opts.timeoutSec = some(120.0)

    let result = client.systemOne(liveTicketState, liveUrgencyQuestions(), opts)
    check result.isOk
    let resp = result.get()
    check resp.model.len > 0
    let urgent = resp.noul("is_urgent")
    echo "Urgent result: ", urgent
    check urgent.isOk
    check urgent.get().noul >= 0.0
    check urgent.get().noul <= 1.0
    check resp.usage.inputTokens.isSome
    check resp.usage.outputTokens.isSome
