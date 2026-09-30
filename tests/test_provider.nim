import std/unittest
import results
import jev_nim_client/provider
import support

suite "provider limits":
  test "typesafe and ollama limits differ":
    let ts = typesafeProfile.limits()
    let ol = ollamaProfile.limits()
    check ts.maxChoiceOptions == 255
    check ol.maxChoiceOptions == 26
    check ol.maxBodyBytes == 64 * 1024
    check ol.supportsKeepAlive
    check not ts.supportsKeepAlive

  test "listModelsPath per provider":
    check listModelsPath(typesafeProfile) == "/v1/models"
    check listModelsPath(ollamaProfile) == "/api/tags"

suite "provider url normalization":
  test "normalizeBaseUrl strips trailing slashes":
    check normalizeBaseUrl("https://host/api/") == "https://host/api"

  test "normalizeOllamaHost adds scheme and default":
    check normalizeOllamaHost("127.0.0.1:11434") == "http://127.0.0.1:11434"
    check normalizeOllamaHost("") == "http://127.0.0.1:11434"

suite "provider resolveClientConfig":
  test "typesafe requires api key":
    check resolveClientConfig(typesafeAi, "", "https://x.test", "m").isErr

  test "typesafe resolves explicit config":
    let cfg = resolveClientConfig(
      typesafeAi, testApiKey, "https://api.test/", "jev-1",
    ).get()
    check cfg[0] == testApiKey
    check cfg[1] == "https://api.test"
    check cfg[2] == "jev-1"

  test "ollama allows empty api key":
    let cfg = resolveClientConfig(
      ollama, "", "localhost:11434", "nimble",
    ).get()
    check cfg[0] == ""
    check cfg[1] == "http://localhost:11434"
    check cfg[2] == "nimble"

suite "provider keepAlive helpers":
  test "keepAlive variants":
    let d = keepAliveDuration("5m")
    check d.kind == kakDuration
    check d.duration == "5m"
    let s = keepAliveSeconds(30.0)
    check s.kind == kakSeconds
    check s.seconds == 30.0
