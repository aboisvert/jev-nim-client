## Shared fixtures for unit tests.

import std/[tables, options]
import jev_nim_client

const
  sampleSystemOneResponse* = """
{
  "model": "jev-1.13.0",
  "usage": { "input_tokens": 296, "output_tokens": 20 },
  "answers": {
    "is_urgent": { "type": "noul", "noul": 0.95 },
    "department": {
      "type": "choice",
      "choice": "billing",
      "probabilities": { "billing": 0.88, "technical": 0.12 },
      "confidence": 0.81
    },
    "frustration": {
      "type": "score",
      "score": 1.05,
      "legend": { "0": "Calm", "1": "Frustrated", "2": "Very angry" },
      "probabilities": { "0": 0.0, "1": 0.95, "2": 0.05 },
      "confidence": 0.92
    }
  }
}
"""

  sampleModelsResponse* = """
{
  "models": [
    {
      "name": "jev-latest",
      "description": "Latest stable Jev",
      "release_date": "2026-01-01"
    }
  ]
}
"""

  typesafeProfile* = profile(typesafeAi)
  ollamaProfile* = profile(ollama)

  testApiKey* = "ts_test_key_1234567890"

proc sampleQuestions*(): Questions =
  result = initOrderedTable[string, Question]()
  result["is_urgent"] = noul("Does this convey urgency?")

proc fullQuestionSet*(): Questions =
  result = initOrderedTable[string, Question]()
  result["is_urgent"] = noul("Does this convey urgency?")
  var deptCriteria = initOrderedTable[string, string]()
  deptCriteria["billing"] = "Payments and refunds"
  deptCriteria["technical"] = "Bugs and outages"
  result["department"] = choice("Which team should handle this?", deptCriteria)
  var toneCriteria = initOrderedTable[string, string]()
  toneCriteria["calm"] = "Calm"
  toneCriteria["angry"] = "Angry"
  result["tone"] = choice("What is the tone?", toneCriteria)
  result["tone"].choice.criteria["angry"] = none(JsonContent)
  result["frustration"] = score(
    "How frustrated is the customer?", "Calm", "Frustrated", "Very angry",
  )
