## Shared payloads and guards for live end-to-end tests.

import std/[os, tables]
import jev_nim_client

const liveTicketState* =
  "Our checkout has returned 500 errors since 9am."

proc e2eEnabled*(): bool =
  getEnv("JEV_RUN_E2E", "") == "1"

proc liveUrgencyQuestions*(): Questions =
  result = initOrderedTable[string, Question]()
  result["is_urgent"] = noul("Does this message convey urgency?")
