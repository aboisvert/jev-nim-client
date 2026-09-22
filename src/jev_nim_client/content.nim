import std/tables

type
  JsonValueKind* = enum
    jvkNull, jvkString, jvkInt, jvkFloat, jvkBool, jvkArray, jvkObject

  JsonValue* = object
    valueKind*: JsonValueKind
    s*: string
    i*: int64
    f*: float
    b*: bool
    arr*: seq[JsonValue]
    obj*: OrderedTable[string, JsonValue]

  JsonContentKind* = enum
    jckString, jckObject, jckArray

  JsonContent* = object
    contentKind*: JsonContentKind
    text*: string
    obj*: OrderedTable[string, JsonValue]
    arr*: seq[JsonValue]

proc jsonNull*(): JsonValue =
  JsonValue(valueKind: jvkNull)

proc jsonStr*(s: string): JsonValue =
  JsonValue(valueKind: jvkString, s: s)

proc jsonInt*(i: int | int64): JsonValue =
  JsonValue(valueKind: jvkInt, i: int64(i))

proc jsonFloat*(f: float): JsonValue =
  JsonValue(valueKind: jvkFloat, f: f)

proc jsonBool*(b: bool): JsonValue =
  JsonValue(valueKind: jvkBool, b: b)

proc jsonArr*(items: openArray[JsonValue]): JsonValue =
  JsonValue(valueKind: jvkArray, arr: @items)

proc jsonObj*(pairs: OrderedTable[string, JsonValue]): JsonValue =
  JsonValue(valueKind: jvkObject, obj: pairs)

proc content*(text: string): JsonContent =
  JsonContent(contentKind: jckString, text: text)

proc jsonContentObj*(pairs: OrderedTable[string, JsonValue]): JsonContent =
  JsonContent(contentKind: jckObject, obj: pairs)

proc jsonContentArr*(items: openArray[JsonValue]): JsonContent =
  JsonContent(contentKind: jckArray, arr: @items)

proc stateText*(text: string): JsonContent =
  content(text)
