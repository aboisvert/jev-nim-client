import std/[tables, options]
import content

type
  NoulCriteria* = object
    trueDesc*: Option[JsonContent]
    falseDesc*: Option[JsonContent]

  Noul* = object
    instructions*: Option[JsonContent]
    criteria*: Option[NoulCriteria]

  Choice* = object
    instructions*: Option[JsonContent]
    criteria*: OrderedTable[string, Option[JsonContent]]

  Score* = object
    instructions*: Option[JsonContent]
    criteria*: seq[JsonContent]

  QuestionKind* = enum
    qkNoul, qkChoice, qkScore

  Question* = object
    questionKind*: QuestionKind
    noul*: Noul
    choice*: Choice
    score*: Score

  Questions* = OrderedTable[string, Question]
  # OrderedTable keeps question id order stable in JSON (matches other TypeSafe SDKs).

proc noul*(instructions: string): Question =
  Question(questionKind: qkNoul, noul: Noul(instructions: some content(instructions)))

proc noul*(instructions: JsonContent): Question =
  Question(questionKind: qkNoul, noul: Noul(instructions: some instructions))

proc noul*(
    instructions: string,
    criteria: NoulCriteria,
): Question =
  Question(
    questionKind: qkNoul,
    noul: Noul(instructions: some content(instructions), criteria: some criteria),
  )

proc noulCriteria*(trueDesc, falseDesc: string): NoulCriteria =
  NoulCriteria(
    trueDesc: some content(trueDesc),
    falseDesc: some content(falseDesc),
  )

proc choice*(instructions: string; criteria: OrderedTable[string, string]): Question =
  var mapped = initOrderedTable[string, Option[JsonContent]]()
  for k, v in criteria:
    mapped[k] = some content(v)
  Question(
    questionKind: qkChoice,
    choice: Choice(instructions: some content(instructions), criteria: mapped),
  )

proc choice*(instructions: string; criteria: OrderedTable[string, Option[JsonContent]]): Question =
  Question(
    questionKind: qkChoice,
    choice: Choice(instructions: some content(instructions), criteria: criteria),
  )

proc choice*(instructions: JsonContent; criteria: OrderedTable[string, Option[JsonContent]]): Question =
  Question(
    questionKind: qkChoice,
    choice: Choice(instructions: some instructions, criteria: criteria),
  )

proc score*(instructions: string; levels: varargs[string]): Question =
  var crit = newSeqOfCap[JsonContent](levels.len)
  for level in levels:
    crit.add content(level)
  Question(
    questionKind: qkScore,
    score: Score(instructions: some content(instructions), criteria: crit),
  )

proc score*(instructions: JsonContent; levels: openArray[JsonContent]): Question =
  Question(
    questionKind: qkScore,
    score: Score(instructions: some instructions, criteria: @levels),
  )
