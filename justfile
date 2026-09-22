# Load TYPESAFE_API_KEY (and other vars) from `.env` in the project root.
set dotenv-load

# HTTPS calls require OpenSSL (Nim's std/httpclient).
nim_flags := "-d:ssl"
nim_src := nim_flags + " --path:src"
nim_examples := nim_flags + " --path:src --path:examples"

# Example program basenames (without .nim)
examples := "quickstart system_one_batch list_models structured_state async_system_one confidence_routing result_handling"

default:
    @just --list

# Compile all example binaries (no network).
build: build-examples build-tests

build-examples:
    #!/usr/bin/env bash
    set -euo pipefail
    for name in {{examples}}; do
      nim c {{nim_examples}} "examples/${name}.nim"
    done

build-tests:
    nim c {{nim_src}} tests/test_jev_client.nim

# Run unit tests.
test:
    nim c -r {{nim_src}} tests/test_jev_client.nim

# Same as `nimble examples`.
examples: build-examples

# Run one example: `just run quickstart`
run example:
    nim r {{nim_examples}} examples/{{example}}.nim

quickstart:
    just run quickstart

system-one-batch:
    just run system_one_batch

list-models:
    just run list_models

structured-state:
    just run structured_state

async-system-one:
    just run async_system_one

confidence-routing:
    just run confidence_routing

result-handling:
    just run result_handling

clean:
    rm -f examples/quickstart examples/system_one_batch examples/list_models \
      examples/structured_state examples/async_system_one examples/confidence_routing \
      examples/result_handling examples/support tests/test_jev_client
