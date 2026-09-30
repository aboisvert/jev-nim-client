## Live System One against local Ollama decision API (Ollama v0.35+ and nimble model).
##
## Run: JEV_RUN_E2E=1 nimble e2e
## Pull model first: ollama pull nimble

import std/[unittest, options, os]
import results
import jev_nim_client
import jev_nim_client/constants
import e2e_support

suite "e2e ollama":
  test "systemOne against Ollama decision API":
    if not e2eEnabled():
      echo "[skip] set JEV_RUN_E2E=1 to run live tests"
      skip()

    let model =
      if getEnv("OLLAMA_DEFAULT_MODEL", "").len > 0:
        getEnv("OLLAMA_DEFAULT_MODEL")
      else:
        DefaultOllamaModel

    let client = newJevClient(provider = ollama, defaultModel = model).get()
    defer:
      client.close()

    var opts = defaultRequestOptions()
    opts.timeoutSec = some(300.0)

    let result = client.systemOne(liveTicketState, liveUrgencyQuestions(), opts)
    if result.isErr:
      let failure = result.unsafeError
      case failure.failureKind
      of jfkConnection, jfkTimeout:
        echo "[skip] Ollama not reachable at " &
          getEnv("OLLAMA_HOST", "http://127.0.0.1:11434") & ": " & failure.message()
        skip()
      of jfkApi:
        if failure.status == 404:
          echo "[skip] model not found (try: ollama pull " & model & ")"
          skip()
        else:
          check result.isOk
      else:
        check result.isOk
    else:
      let resp = result.get()
      #echo resp
      check resp.model.len > 0
      let urgent = resp.noul("is_urgent")
      echo "Urgent result: ", urgent
      check urgent.isOk
      check urgent.get().noul >= 0.0
      check urgent.get().noul <= 1.0

