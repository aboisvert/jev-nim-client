## Compare ``Result`` returns with raising helpers.
##
## Run (uses a fake missing key unless you export TYPESAFE_API_KEY):
##   nim r --path:src --path:examples examples/result_handling.nim

import std/os
import jev_nim_client
import jev_nim_client/constants

proc demoResult() =
  let key = getEnv(ApiKeyEnv, "")
  let clientResult = newJevClient(apiKey = key)
  if clientResult.isErr:
    echo "Result path: ", clientResult.error.message()
    return
  let client = clientResult.unwrap()
  defer:
    client.close()
  echo "Result path: client created"

proc demoRaise() =
  try:
    discard newJevClientOrRaise(apiKey = getEnv(ApiKeyEnv, ""))
    echo "Raise path: client created"
  except JevError as e:
    echo "Raise path: ", e.msg

proc main() =
  echo "=== Result[T, JevFailure] ==="
  demoResult()
  echo ""
  echo "=== OrRaise / exceptions ==="
  demoRaise()

main()
