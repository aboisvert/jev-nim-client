## Minimal Result type (compatible with common Result call patterns).

type
  Result*[T, E] = object
    case ok*: bool
    of true:
      when T is void:
        discard
      else:
        v*: T
    of false:
      e*: E

proc ok*[T, E](v: T): Result[T, E] =
  when T is void:
    Result[T, E](ok: true)
  else:
    Result[T, E](ok: true, v: v)

proc ok*[E](): Result[void, E] =
  Result[void, E](ok: true)

proc err*[T, E](e: E): Result[T, E] =
  Result[T, E](ok: false, e: e)

func isOk*[T, E](r: Result[T, E]): bool =
  r.ok

func isErr*[T, E](r: Result[T, E]): bool =
  not r.ok

func unwrap*[T, E](r: Result[T, E]): T =
  if not r.ok:
    raise newException(ValueError, "Result is err")
  when T is void:
    discard
  else:
    r.v

func error*[T, E](r: Result[T, E]): E =
  if r.ok:
    raise newException(ValueError, "Result is ok")
  r.e

template valueOr*(r: Result; errBody: untyped): untyped =
  if r.ok:
    when compiles(r.v):
      r.v
    else:
      discard
  else:
    let failure {.inject.} = r.e
    errBody
