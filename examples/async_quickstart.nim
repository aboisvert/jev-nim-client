## Async quick start — same flow as ``quickstart.nim`` with ``AsyncJevClient`` (``await`` / ``waitFor``).
##
## Run:
##   export TYPESAFE_API_KEY=ts_...
##   nim r --path:src --path:examples examples/async_quickstart.nim

import std/[asyncdispatch, tables, strformat]
import jev_nim_client
import support

proc main() {.async.} =
  let client = openAsyncClient()
  defer:
    client.close()

  var questions = initOrderedTable[string, Question]()
  questions["billing"] = noul("Is this about billing?")
  var tone = initOrderedTable[string, string]()
  tone["calm"] = "Calm, neutral wording"
  tone["angry"] = "Angry or escalatory wording"
  questions["tone"] = choice("What is the tone?", tone)

  let systemOneResult = await client.systemOne(ExampleState, questions)
  if systemOneResult.isErr:
    echo "systemOne failed: ", systemOneResult.unsafeError.message()
    quit 1
  let result = systemOneResult.get()

  echo "model: ", result.model
  let billing = result.noul("billing").get()
  echo &"billing (0–1 yes): {billing.noul:.2f}"
  let toneAns = result.choice("tone").get()
  echo &"tone: {toneAns.choice} (confidence {toneAns.confidence:.2f})"

waitFor main()
