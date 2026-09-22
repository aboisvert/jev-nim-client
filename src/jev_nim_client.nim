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
## Async usage: ``import jev_nim_client/asyncclient``

import jev_nim_client/syncclient
import jev_nim_client/asyncclient

export syncclient
export asyncclient
