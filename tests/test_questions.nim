import std/[unittest, tables, options]
import jev_nim_client/questions

suite "questions builders":
  test "noul with custom criteria":
    let q = noul("Is refund requested?", noulCriteria("Yes", "No"))
    check q.questionKind == qkNoul
    check q.noul.criteria.isSome
    check q.noul.criteria.get().trueDesc.get().text == "Yes"

  test "choice from string map and score varargs":
    var criteria = initOrderedTable[string, string]()
    criteria["a"] = "A"
    criteria["b"] = "B"
    let ch = choice("Pick", criteria)
    check ch.questionKind == qkChoice
    check ch.choice.criteria.len == 2
    let sc = score("Rate", "Low", "High")
    check sc.score.criteria.len == 2
