## Environment variable names and client defaults (aligned with the official TypeSafe SDKs).

const
  ApiKeyEnv* = "TYPESAFE_API_KEY"
  BaseUrlEnv* = "TYPESAFE_BASE_URL"
  DefaultModelEnv* = "TYPESAFE_DEFAULT_MODEL"

  OllamaHostEnv* = "OLLAMA_HOST"
  OllamaApiKeyEnv* = "OLLAMA_API_KEY"
  OllamaDefaultModelEnv* = "OLLAMA_DEFAULT_MODEL"

  DefaultBaseUrl* = "https://api.typesafe.ai"
  DefaultModel* = "jev-latest"
  DefaultOllamaHost* = "http://127.0.0.1:11434"
  DefaultOllamaModel* = "nimble"
  DefaultTimeoutSec* = 10.0
  ClientVersion* = "0.1.0"
  UserAgentPrefix* = "jev-nim-client"

  SystemOnePath* = "/v1/systemone"
  ModelsPath* = "/v1/models"

  RequestIdHeader* = "x-typesafe-request-id"
