## Nim client for the TypeSafe System One (Jev) API.
##
## Sync usage:
##
## .. code-block:: nim
##    import jev_nim_client
##    let client = newJevClient(apiKey = "ts_...").unwrap()
##    defer: client.close()
##    let result = client.systemOne(
##      "Help! My payouts have been failing.",
##      initOrderedTable({"is_urgent": noul("Does this convey urgency?")}),
##    ).unwrap()
##
## Async usage (``AsyncJevClient`` methods are ``{.async.}`` — ``await`` inside an async proc,
## or ``waitFor`` from sync code):
##
## .. code-block:: nim
##    import std/asyncdispatch
##    import jev_nim_client
##    proc main() {.async.} =
##      let client = newAsyncJevClient().unwrap()
##      defer: client.close()
##      let result = (await client.systemOne("Help!", questions)).unwrap()
##    waitFor main()
##
## Runnable async examples: ``examples/async_quickstart.nim``, ``examples/async_system_one.nim``.

import jev_nim_client/syncclient
import jev_nim_client/asyncclient

export syncclient
export asyncclient
