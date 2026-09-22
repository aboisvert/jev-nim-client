## Ask several questions in one System One call (speculative fan-out pattern).
##
## Run:
##   export TYPESAFE_API_KEY=ts_...
##   nim r --path:src --path:examples examples/system_one_batch.nim

import std/[options, strformat, tables]
import jev_nim_client
import support

proc main() =
  let client = openClient()
  defer:
    client.close()

  let questions = billingFanOutQuestions()
  let result = client.systemOneOrRaise(ExampleState, questions)

  echo "model: ", result.model
  if result.usage.inputTokens != none(int):
    echo "input tokens: ", result.usage.inputTokens.get() # usage fields are optional in the API

  let urgent = result.noul("is_urgent").get().noul
  echo &"is_urgent: {urgent:.2f}"

  let dept = result.choice("department").get()
  echo &"department: {dept.choice}"
  for k, p in dept.probabilities:
    echo &"  P({k}) = {p:.2f}"

  let frustration = result.score("frustration").get()
  echo &"frustration score: {frustration.score:.2f} (confidence {frustration.confidence:.2f})"
  # Legend keys ("0", "1", …) align with score level indices in probabilities.
  for idx, label in frustration.legend:
    let prob = frustration.probabilities.getOrDefault(idx, 0.0)
    if label.contentKind == jckString:
      echo &"  level {idx}: {label.text} — {prob:.2f}"

main()
