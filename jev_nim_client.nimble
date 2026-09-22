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

task test, "Run unit tests":
  exec "nim c -r " & nimFlags & " --path:src tests/test_jev_client.nim"

task examples, "Compile example programs":
  exec "nim c " & nimFlags & " --path:src --path:examples examples/quickstart.nim"
  exec "nim c " & nimFlags & " --path:src --path:examples examples/system_one_batch.nim"
  exec "nim c " & nimFlags & " --path:src --path:examples examples/list_models.nim"
  exec "nim c " & nimFlags & " --path:src --path:examples examples/structured_state.nim"
  exec "nim c " & nimFlags & " --path:src --path:examples examples/async_quickstart.nim"
  exec "nim c " & nimFlags & " --path:src --path:examples examples/async_system_one.nim"
  exec "nim c " & nimFlags & " --path:src --path:examples examples/confidence_routing.nim"
  exec "nim c " & nimFlags & " --path:src --path:examples examples/result_handling.nim"
