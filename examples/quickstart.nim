## Quick start — mirrors the billing support example from the TypeSafe API docs.
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
  questions["billing"] = noul("Is this about billing?")
  var tone = initOrderedTable[string, string]()
  tone["calm"] = "Calm, neutral wording"
  tone["angry"] = "Angry or escalatory wording"
  questions["tone"] = choice("What is the tone?", tone)

  let result = client.systemOne(ExampleState, questions).valueOr:
    echo "systemOne failed: ", failure.message()
    quit 1

  echo "model: ", result.model
  let billing = result.noul("billing").unwrap()
  echo &"billing (0–1 yes): {billing.noul:.2f}"
  let toneAns = result.choice("tone").unwrap()
  echo &"tone: {toneAns.choice} (confidence {toneAns.confidence:.2f})"

main()
