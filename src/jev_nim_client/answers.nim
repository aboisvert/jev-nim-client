import std/[tables, options]
import content, results

type
  Usage* = object
    inputTokens*: Option[int]
    outputTokens*: Option[int]

  NoulAnswer* = object
    noul*: float

  ChoiceAnswer* = object
    choice*: string
    probabilities*: OrderedTable[string, float]
    confidence*: float

  ScoreAnswer* = object
    score*: float
    legend*: OrderedTable[string, JsonContent]
    probabilities*: OrderedTable[string, float]
    confidence*: float

  AnswerKind* = enum
    akNoul, akChoice, akScore

  Answer* = object
    case answerKind*: AnswerKind
    of akNoul:
      noulAns*: NoulAnswer
    of akChoice:
      choiceAns*: ChoiceAnswer
    of akScore:
      scoreAns*: ScoreAnswer
  # One variant per question type; unused fields stay at default zero values.

  SystemOneResponse* = object
    model*: string
    usage*: Usage
    answers*: OrderedTable[string, Answer]
    requestId*: string

  ModelMetadata* = object
    name*: string
    description*: string
    releaseDate*: string

  ListModelsResponse* = object
    models*: seq[ModelMetadata]
    requestId*: string

proc noul*(resp: SystemOneResponse; id: string): Result[NoulAnswer, string] =
  if id notin resp.answers:
    return err("answer not found: " & id)
  let ans = resp.answers[id]
  if ans.answerKind != akNoul:
    return err("answer '" & id & "' is not a noul")
  ok(ans.noulAns)

proc choice*(resp: SystemOneResponse; id: string): Result[ChoiceAnswer, string] =
  if id notin resp.answers:
    return err("answer not found: " & id)
  let ans = resp.answers[id]
  if ans.answerKind != akChoice:
    return err("answer '" & id & "' is not a choice")
  ok(ans.choiceAns)

proc score*(resp: SystemOneResponse; id: string): Result[ScoreAnswer, string] =
  if id notin resp.answers:
    return err("answer not found: " & id)
  let ans = resp.answers[id]
  if ans.answerKind != akScore:
    return err("answer '" & id & "' is not a score")
  ok(ans.scoreAns)

proc nouls*(resp: SystemOneResponse): OrderedTable[string, NoulAnswer] =
  result = initOrderedTable[string, NoulAnswer]()
  for id, ans in resp.answers:
    if ans.answerKind == akNoul:
      result[id] = ans.noulAns

proc choices*(resp: SystemOneResponse): OrderedTable[string, ChoiceAnswer] =
  result = initOrderedTable[string, ChoiceAnswer]()
  for id, ans in resp.answers:
    if ans.answerKind == akChoice:
      result[id] = ans.choiceAns

proc scores*(resp: SystemOneResponse): OrderedTable[string, ScoreAnswer] =
  result = initOrderedTable[string, ScoreAnswer]()
  for id, ans in resp.answers:
    if ans.answerKind == akScore:
      result[id] = ans.scoreAns
