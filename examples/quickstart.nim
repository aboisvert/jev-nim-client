## Quick start — mirrors the billing support example from the TypeSafe API docs.
## For the async client, see ``examples/async_quickstart.nim``.
##
## Run:
##   export TYPESAFE_API_KEY=ts_...
##   nim r --path:src --path:examples examples/quickstart.nim

import std/[tables, strformat]
import jev_nim_client
import support

proc main() =
  let client = openClient()
  defer:
    client.close()

  var questions = initOrderedTable[string, Question]()
  # Table keys are answer ids — use the same string in result.noul("billing"), etc.
  questions["billing"] = noul("Is this about billing?")
  var tone = initOrderedTable[string, string]()
  tone["calm"] = "Calm, neutral wording"
  tone["angry"] = "Angry or escalatory wording"
  questions["tone"] = choice("What is the tone?", tone)

  let result = client.systemOne(ExampleState, questions).valueOr:
    echo "systemOne failed: ", error.message()
    quit 1

  echo "model: ", result.model
  let billing = result.noul("billing").get()
  echo &"billing (0–1 yes): {billing.noul:.2f}" # noul answers are continuous, not a hard true/false
  let toneAns = result.choice("tone").get()
  echo &"tone: {toneAns.choice} (confidence {toneAns.confidence:.2f})"

main()
