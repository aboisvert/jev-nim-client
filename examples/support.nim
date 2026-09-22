## Shared helpers for example programs (import with ``--path:examples``).
import std/[os, strutils, tables]
import jev_nim_client
import jev_nim_client/constants

const ExampleState* =
  "Help! My payouts have been failing for 3 days."

proc ensureApiKey*() =
  # Examples use quit for brevity; library callers should prefer Result instead.
  if getEnv(ApiKeyEnv, "").strip().len == 0:
    echo "Set ", ApiKeyEnv, " to your TypeSafe API key, then re-run."
    quit 1

proc openClient*(): JevClient =
  ensureApiKey()
  newJevClient().valueOr:
    echo "Could not create client: ", failure.message()
    quit 1

proc openAsyncClient*(): AsyncJevClient =
  ensureApiKey()
  newAsyncJevClient().valueOr:
    echo "Could not create client: ", failure.message()
    quit 1

proc billingFanOutQuestions*(): Questions =
  # Several unrelated questions in one systemOne call — one HTTP round trip, shared state context.
  var questions = initOrderedTable[string, Question]()
  questions["is_urgent"] = noul(
    "Does this convey urgency?",
    noulCriteria("Explicitly time-sensitive", "No urgency expressed"),
  )
  var dept = initOrderedTable[string, string]()
  # Map keys become choice option ids in the API response (dept.choice, probabilities, etc.).
  dept["billing"] = "Payments, invoicing, refunds"
  dept["technical"] = "Bugs, outages, integrations"
  dept["sales"] = "Pricing, upgrades, new accounts"
  questions["department"] = choice("Which team should handle this?", dept)
  questions["frustration"] = score(
    "How frustrated is the customer?", "Calm", "Frustrated", "Very angry",
  )
  questions
