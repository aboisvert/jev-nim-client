import std/[unittest, tables]
import results
import jev_nim_client
import jev_nim_client/wire
import support

suite "answers accessors":
  test "typed getters and plural filters":
    var headers = initTable[string, string]()
    let resp = decodeSystemOneResponse(sampleSystemOneResponse, headers).get()
    check resp.noul("is_urgent").get().noul == 0.95
    check resp.nouls().len == 1
    check resp.choices().len == 1
    check resp.scores().len == 1

  test "getters fail for missing id or wrong kind":
    var headers = initTable[string, string]()
    let resp = decodeSystemOneResponse(sampleSystemOneResponse, headers).get()
    check resp.noul("missing").isErr
    check resp.choice("is_urgent").isErr
    check resp.score("department").isErr
