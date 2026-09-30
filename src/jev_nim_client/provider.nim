## Provider profiles: TypeSafe cloud vs local Ollama System One.

import std/[os, strutils]
import constants, errors, results

type
  ProviderKind* = enum
    typesafeAi, ollama

  ProviderLimits* = object
    minChoiceOptions*: int
    maxChoiceOptions*: int
    minScoreLevels*: int
    maxScoreLevels*: int
    maxQuestions*: int
    maxBodyBytes*: int
    stringCriteriaOnly*: bool
    requiresNonemptyStringState*: bool
    requiresNonemptyInstructions*: bool
    supportsKeepAlive*: bool

  KeepAliveKind* = enum
    kakDuration, kakSeconds

  KeepAlive* = object
    case kind*: KeepAliveKind
    of kakDuration:
      duration*: string
    of kakSeconds:
      seconds*: float

  ProviderProfile* = object
    kind*: ProviderKind

proc limits*(profile: ProviderProfile): ProviderLimits =
  case profile.kind
  of typesafeAi:
    ProviderLimits(
      minChoiceOptions: 1,
      maxChoiceOptions: 255,
      minScoreLevels: 2,
      maxScoreLevels: 10,
      maxQuestions: high(int),
      maxBodyBytes: 0,
      stringCriteriaOnly: false,
      requiresNonemptyStringState: false,
      requiresNonemptyInstructions: false,
      supportsKeepAlive: false,
    )
  of ollama:
    ProviderLimits(
      minChoiceOptions: 2,
      maxChoiceOptions: 26,
      minScoreLevels: 2,
      maxScoreLevels: 26,
      maxQuestions: 64,
      maxBodyBytes: 64 * 1024,
      stringCriteriaOnly: true,
      requiresNonemptyStringState: true,
      requiresNonemptyInstructions: true,
      supportsKeepAlive: true,
    )

proc profile*(kind: ProviderKind): ProviderProfile =
  ProviderProfile(kind: kind)

proc listModelsPath*(profile: ProviderProfile): string =
  case profile.kind
  of typesafeAi: "/v1/models"
  of ollama: "/api/tags"

proc keepAliveDuration*(duration: string): KeepAlive =
  KeepAlive(kind: kakDuration, duration: duration)

proc keepAliveSeconds*(seconds: float): KeepAlive =
  KeepAlive(kind: kakSeconds, seconds: seconds)

proc normalizeBaseUrl*(url: string): string =
  var u = url.strip()
  while u.len > 0 and u[^1] == '/':
    u.setLen(u.len - 1)
  u

proc normalizeOllamaHost*(host: string): string =
  var u = normalizeBaseUrl(host)
  if u.len == 0:
    return "http://127.0.0.1:11434"
  if "://" notin u:
    u = "http://" & u
  u

proc resolveClientConfig*(
    provider: ProviderKind;
    apiKeyArg, baseUrlArg, defaultModelArg: string,
): Result[(string, string, string), JevFailure] =
  case provider
  of typesafeAi:
    let rawKey =
      if apiKeyArg.len > 0:
        apiKeyArg
      else:
        getEnv(ApiKeyEnv, "")
    let key = ?validateApiKey(rawKey)
    let resolvedBase =
      if baseUrlArg.len > 0:
        normalizeBaseUrl(baseUrlArg)
      else:
        normalizeBaseUrl(envOrDefault(BaseUrlEnv, DefaultBaseUrl))
    let resolvedModel =
      if defaultModelArg.len > 0:
        defaultModelArg.strip()
      else:
        envOrDefault(DefaultModelEnv, DefaultModel)
    ok((key, resolvedBase, resolvedModel))
  of ollama:
    let rawKey =
      if apiKeyArg.len > 0:
        apiKeyArg
      else:
        getEnv(OllamaApiKeyEnv, "")
    let key =
      if rawKey.len == 0:
        ""
      else:
        ?validateApiKey(rawKey)
    let resolvedBase =
      if baseUrlArg.len > 0:
        normalizeOllamaHost(baseUrlArg)
      else:
        normalizeOllamaHost(envOrDefault(OllamaHostEnv, DefaultOllamaHost))
    let resolvedModel =
      if defaultModelArg.len > 0:
        defaultModelArg.strip()
      else:
        envOrDefault(OllamaDefaultModelEnv, DefaultOllamaModel)
    ok((key, resolvedBase, resolvedModel))
