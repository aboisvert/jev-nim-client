## Route by confidence — act automatically only when the choice is confident enough.
##
## Inspired by TypeSafe's confidence-gated routing pattern.
##
## Run:
##   export TYPESAFE_API_KEY=ts_...
##   nim r --path:src --path:examples examples/confidence_routing.nim

import std/[strformat, tables]
import jev_nim_client
import support

const ConfidenceThreshold = 0.75

proc main() =
  let client = openClient()
  defer:
    client.close()

  var questions = initOrderedTable[string, Question]()
  var dept = initOrderedTable[string, string]()
  dept["billing"] = "Payments, invoicing, refunds"
  dept["technical"] = "Bugs, outages, integrations"
  dept["sales"] = "Pricing, upgrades, new accounts"
  questions["department"] = choice("Which team should handle this?", dept)

  let result = client.systemOne(ExampleState, questions).valueOr:
    echo "systemOne failed: ", failure.message()
    quit 1
  let route = result.choice("department").valueOr:
    echo "missing answer for department: ", failure
    quit 1

  echo "result: ", result
  echo ""

  if route.confidence >= ConfidenceThreshold:
    echo &"AUTO-ROUTE → {route.choice} (confidence {route.confidence:.2f})"
  else:
    echo &"REVIEW — top choice {route.choice} but confidence only {route.confidence:.2f}"
    echo "Probabilities:"
    for k, p in route.probabilities:
      echo &"  {k}: {p:.2f}"

main()
