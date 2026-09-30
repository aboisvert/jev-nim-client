import std/[unittest, tables, json]
import results
import jev_nim_client/content
import jev_nim_client/wire

suite "content and json codec":
  test "JsonValue constructors":
    check jsonNull().valueKind == jvkNull
    check jsonStr("a").s == "a"
    check jsonInt(42).i == 42'i64
    check jsonBool(true).b

  test "encodeJsonValue roundtrip through decodeJsonValue":
    var inner = initOrderedTable[string, JsonValue]()
    inner["n"] = jsonInt(1)
    let original = jsonObj(inner)
    let node = encodeJsonValue(original)
    let back = decodeJsonValue(node).get()
    check back.valueKind == jvkObject
    check back.obj["n"].i == 1

  test "encodeJsonContent for string object and array":
    check encodeJsonContent(content("hi")).getStr() == "hi"
    var obj = initOrderedTable[string, JsonValue]()
    obj["k"] = jsonStr("v")
    check encodeJsonContent(jsonContentObj(obj)).kind == JObject
    check encodeJsonContent(jsonContentArr(@[jsonInt(1)])).kind == JArray
