# jev-nim-client

Nim client library for the [TypeSafe](https://typesafe.ai) **System One (Jev)** API. Send application state (text or structured JSON) together with one or more questions; the API returns calibrated answers in a single HTTP round trip.

Features:

- **Sync** (`JevClient`) and **async** (`AsyncJevClient`) clients
- **`Result[T, JevFailure]`** by default, plus `*OrRaise` helpers that map failures to typed exceptions
- Question types: **noul** (continuous yes/no), **choice**, and **score**
- Retries, timeouts, and per-request options
- **TypeSafe** or **Ollama** providers (`typesafeAi` / `ollama`) with shared question types
- Defaults aligned with the official TypeSafe SDKs (env vars, base URL, models)

## Requirements

- [Nim](https://nim-lang.org/) **≥ 2.2.12**
- OpenSSL (HTTPS via `std/httpclient`); compile with `-d:ssl`

## Installation

From a checkout (local path):

```bash
nimble install -y --path:.
```

Or add the package path when compiling:

```bash
nim c -d:ssl --path:src your_app.nim
```

## Configuration

Pass `provider = typesafeAi` (default) or `provider = ollama` to `newJevClient` / `newAsyncJevClient`, along with optional `apiKey`, `baseUrl`, and `defaultModel`. Empty arguments fall back to the env vars for that provider.

### TypeSafe (default)

| Variable | Purpose | Default |
|----------|---------|---------|
| `TYPESAFE_API_KEY` | API key (`ts_...`) | *(required)* |
| `TYPESAFE_BASE_URL` | API base URL | `https://api.typesafe.ai` |
| `TYPESAFE_DEFAULT_MODEL` | Model for `systemOne` | `jev-latest` |

### Ollama (local System One)

Requires [Ollama](https://ollama.com) **v0.35.0+** and a System One model (for example `ollama pull nimble`). See the [Ollama decision guide](https://docs.ollama.com/capabilities/decision).

| Variable | Purpose | Default |
|----------|---------|---------|
| `OLLAMA_HOST` | Ollama base URL | `http://127.0.0.1:11434` |
| `OLLAMA_DEFAULT_MODEL` | Model for `systemOne` | `nimble` |
| `OLLAMA_API_KEY` | Optional bearer token | *(unset)* |

Ollama enforces stricter request limits (for example 64 KiB body size, up to 64 questions, choice/score criteria as strings). Use `RequestOptions.keepAlive` with `keepAliveDuration("5m")` or `keepAliveSeconds(...)` to control model load time after a request.

## Quick start (sync)

```nim
import std/tables
import jev_nim_client

proc main() =
  let client = newJevClient(apiKey = "ts_...").get()
  defer: client.close()

  var questions = initOrderedTable[string, Question]()
  questions["billing"] = noul("Is this about billing?")

  let state = "Help! My payouts have been failing for 3 days."
  let result = client.systemOne(state, questions).get()

  echo result.model
  echo result.noul("billing").get().noul  # 0.0–1.0

main()
```

### Quick start (Ollama)

```nim
import std/tables
import jev_nim_client

proc main() =
  let client = newJevClient(provider = ollama).get()
  defer: client.close()

  var questions = initOrderedTable[string, Question]()
  questions["billing"] = noul("Is this about billing?")

  let result = client.systemOne("Help! My payouts have been failing.", questions).get()
  echo result.noul("billing").get().noul

main()
```

Table keys are **answer ids** — use the same id in `result.noul("billing")`, `result.choice("tone")`, etc.

## Async client

`AsyncJevClient` methods are `{.async.}`; use `await` inside an async proc or `waitFor` from sync code:

```nim
import std/[asyncdispatch, tables]
import jev_nim_client

proc main() {.async.} =
  let client = newAsyncJevClient().get()
  defer: client.close()
  var questions = initOrderedTable[string, Question]()
  questions["is_urgent"] = noul("Does this convey urgency?")
  let result = (await client.systemOne("Help!", questions)).get()

waitFor main()
```

See `examples/async_quickstart.nim` and `examples/async_system_one.nim`.

## API surface

Import `jev_nim_client` to get sync and async clients plus helpers:

| Operation | Sync | Async |
|-----------|------|-------|
| Create client | `newJevClient` | `newAsyncJevClient` |
| System One | `client.systemOne(state, questions)` | `await client.systemOne(...)` |
| List models | `client.listModels()` | `await client.listModels()` |
| Close | `client.close()` | `client.close()` |

- **State** can be a `string` or structured `JsonContent` (see `examples/structured_state.nim`).
- **Questions** are an `OrderedTable[string, Question]` built with `noul`, `choice`, and `score`.
- **Errors**: library APIs return [`results`](https://github.com/arnetheduck/nim-results) `Result` values — use `isErr` / `.error`, `.get()`, `?` inside procs, `.valueOr:` (with `error` in the block), or `*OrRaise` helpers and catch `JevError` subclasses.

## Examples

Set your key, then run an example:

```bash
export TYPESAFE_API_KEY=ts_...
```

With [just](https://github.com/casey/just) (loads `.env` from the project root if present):

```bash
just quickstart          # billing support demo (sync)
just async-quickstart    # same flow, async client
just list-models         # GET /v1/models
just system-one-batch    # multiple questions, one call
just structured-state    # JSON state payload
just confidence-routing  # routing on answer confidence
just result-handling     # Result vs exceptions
just test                # unit tests
just build               # compile examples + tests
```

With Nimble:

```bash
nimble test
nimble examples
```

Manual run:

```bash
nim r -d:ssl --path:src --path:examples examples/quickstart.nim
```

| Example | What it shows |
|---------|----------------|
| `quickstart.nim` | noul + choice on support text |
| `async_quickstart.nim` | async equivalent |
| `system_one_batch.nim` | fan-out questions in one request |
| `list_models.nim` | available models |
| `structured_state.nim` | non-string state |
| `confidence_routing.nim` | confidence-based routing |
| `result_handling.nim` | `Result` vs `OrRaise` |

Shared example helpers live in `examples/support.nim` (not part of the library).

## Development

Unit tests are split by module under `tests/` (for example `test_wire.nim`, `test_retry.nim`, `test_sync_client.nim`). Shared fixtures live in `tests/support.nim`; fake HTTP transports are in `tests/fake_transports.nim`.

Live end-to-end tests (`test_e2e_typesafe.nim`, `test_e2e_ollama.nim`) are opt-in: they skip unless `JEV_RUN_E2E=1`. TypeSafe needs `TYPESAFE_API_KEY`; Ollama needs a running server and the `nimble` model (`ollama pull nimble`).

```bash
just test
just build
just clean

# Live providers (network required)
export TYPESAFE_API_KEY=ts_...
just e2e                  # both providers
just e2e-typesafe         # TypeSafe only
just e2e-ollama           # local Ollama only
# or: nimble e2e
```

## License

MIT — see `jev_nim_client.nimble`.
