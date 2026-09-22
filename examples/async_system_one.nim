## Async client — same System One call via ``AsyncJevClient``.
##
## Run:
##   export TYPESAFE_API_KEY=ts_...
##   nim r --path:src --path:examples examples/async_system_one.nim

import std/[asyncdispatch, strformat]
import jev_nim_client
import support

proc main() {.async.} =
  let client = openAsyncClient()
  defer:
    client.close()

  let questions = billingFanOutQuestions()
  let result = client.systemOne(ExampleState, questions).unwrap()
  echo "model: ", result.model
  let dept = result.choice("department").unwrap().choice
  echo &"department: {dept}"

waitFor main() # Nim async entry: proc main {.async.} must be driven from sync top level
