## List models available to your account (GET /v1/models).
##
## Run:
##   export TYPESAFE_API_KEY=ts_...
##   nim r --path:src --path:examples examples/list_models.nim

import std/strformat
import jev_nim_client
import support

proc main() =
  let client = openClient()
  defer:
    client.close()

  let models = client.listModelsOrRaise()
  if models.requestId.len > 0:
    echo "request id: ", models.requestId # from x-typesafe-request-id header, for support tickets
  for m in models.models:
    echo &"{m.name} ({m.releaseDate}) — {m.description}"

main()
