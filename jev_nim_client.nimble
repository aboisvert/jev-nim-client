# Package

version       = "0.1.0"
author        = "Alex Boisvert"
description   = "Nim client library for JEV"
license       = "MIT"
srcDir        = "src"


# Dependencies

requires "nim >= 2.2.12"
requires "results"

# Tasks

const nimFlags = "-d:ssl"

const testModules = @[
  "test_wire",
  "test_retry",
  "test_errors",
  "test_provider",
  "test_content",
  "test_answers",
  "test_questions",
  "test_requestloop",
  "test_sync_client",
  "test_async_client",
]

task test, "Run unit tests":
  for name in testModules:
    exec "nim c -r " & nimFlags & " --path:src --path:tests tests/" & name & ".nim"

const e2eModules = @["test_e2e_typesafe", "test_e2e_ollama"]

task e2e, "Run live provider tests (set TYPESAFE_API_KEY; Ollama optional)":
  when defined(windows):
    for name in e2eModules:
      exec "set JEV_RUN_E2E=1&& nim c -r " & nimFlags & " --path:src --path:tests tests/" & name & ".nim"
  else:
    for name in e2eModules:
      exec "JEV_RUN_E2E=1 nim c -r " & nimFlags & " --path:src --path:tests tests/" & name & ".nim"

task examples, "Compile example programs":
  exec "nim c " & nimFlags & " --path:src --path:examples examples/quickstart.nim"
  exec "nim c " & nimFlags & " --path:src --path:examples examples/system_one_batch.nim"
  exec "nim c " & nimFlags & " --path:src --path:examples examples/list_models.nim"
  exec "nim c " & nimFlags & " --path:src --path:examples examples/structured_state.nim"
  exec "nim c " & nimFlags & " --path:src --path:examples examples/async_quickstart.nim"
  exec "nim c " & nimFlags & " --path:src --path:examples examples/async_system_one.nim"
  exec "nim c " & nimFlags & " --path:src --path:examples examples/confidence_routing.nim"
  exec "nim c " & nimFlags & " --path:src --path:examples examples/result_handling.nim"
