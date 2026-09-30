# Load TYPESAFE_API_KEY (and other vars) from `.env` in the project root.
set dotenv-load

# HTTPS calls require OpenSSL (Nim's std/httpclient).
nim_flags := "-d:ssl"
nim_src := nim_flags + " --path:src"
nim_examples := nim_flags + " --path:src --path:examples"

# Example program basenames (without .nim)
examples := "quickstart async_quickstart system_one_batch list_models structured_state async_system_one confidence_routing result_handling"

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

test_modules := "test_wire test_retry test_errors test_provider test_content test_answers test_questions test_requestloop test_sync_client test_async_client"

build-tests:
    #!/usr/bin/env bash
    set -euo pipefail
    for name in {{test_modules}}; do
      nim c {{nim_src}} --path:tests "tests/${name}.nim"
    done

# Run unit tests.
test:
    #!/usr/bin/env bash
    set -euo pipefail
    for name in {{test_modules}}; do
      nim c -r {{nim_src}} --path:tests "tests/${name}.nim"
    done

e2e_modules := "test_e2e_typesafe test_e2e_ollama"

# Live tests against TypeSafe and Ollama (needs JEV_RUN_E2E=1, network, credentials).
e2e:
    #!/usr/bin/env bash
    set -euo pipefail
    export JEV_RUN_E2E=1
    for name in {{e2e_modules}}; do
      nim c -r {{nim_src}} --path:tests "tests/${name}.nim"
    done

e2e-typesafe:
    JEV_RUN_E2E=1 nim c -r {{nim_src}} --path:tests tests/test_e2e_typesafe.nim

e2e-ollama:
    JEV_RUN_E2E=1 nim c -r {{nim_src}} --path:tests tests/test_e2e_ollama.nim

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

async-quickstart:
    just run async_quickstart

async-system-one:
    just run async_system_one

confidence-routing:
    just run confidence_routing

result-handling:
    just run result_handling

clean:
    rm -f examples/quickstart examples/async_quickstart examples/system_one_batch examples/list_models \
      examples/structured_state examples/async_system_one examples/confidence_routing \
      examples/result_handling examples/support tests/test_*
