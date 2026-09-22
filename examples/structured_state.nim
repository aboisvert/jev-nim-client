## Structured `state` and structured question `instructions` (API advanced structure).
##
## Run:
##   export TYPESAFE_API_KEY=ts_...
##   nim r --path:src --path:examples examples/structured_state.nim

import std/[tables, strformat]
import jev_nim_client
import support

proc main() =
  let client = openClient()
  defer:
    client.close()

  var stateObj = initOrderedTable[string, JsonValue]()
  stateObj["subject"] = jsonStr("Payout failure")
  stateObj["body"] = jsonStr(ExampleState)
  stateObj["channel"] = jsonStr("email")
  let state = jsonContentObj(stateObj) # state can be JSON object, not only a plain string

  var duplicateRef = initOrderedTable[string, JsonValue]()
  duplicateRef["name"] = jsonStr("John Smith")
  duplicateRef["location"] = jsonStr("Oakland, California")
  duplicateRef["last_employer"] = jsonStr("Google")
  var instructionsObj = initOrderedTable[string, JsonValue]()
  instructionsObj["potential_duplicate"] = jsonObj(duplicateRef)
  instructionsObj["question"] = jsonStr(
    "Is the message from the same person as `potential_duplicate`?",
  )
  let instructions = jsonContentObj(instructionsObj)
  # noul() accepts JsonContent instructions so the model sees structured context, not one blob.

  var questions = initOrderedTable[string, Question]()
  questions["same_person"] = noul(instructions)

  let result = client.systemOne(state, questions).unwrap()
  let ans = result.noul("same_person").unwrap()
  echo &"same_person (probability yes): {ans.noul:.2f}"

main()
