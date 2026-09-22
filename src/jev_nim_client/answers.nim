import std/[tables, options]
import content, results_shim

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
    answerKind*: AnswerKind
    noulAns*: NoulAnswer
    choiceAns*: ChoiceAnswer
    scoreAns*: ScoreAnswer

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
    return err[NoulAnswer, string]("answer not found: " & id)
  let ans = resp.answers[id]
  if ans.answerKind != akNoul:
    return err[NoulAnswer, string]("answer '" & id & "' is not a noul")
  ok[NoulAnswer, string](ans.noulAns)

proc choice*(resp: SystemOneResponse; id: string): Result[ChoiceAnswer, string] =
  if id notin resp.answers:
    return err[ChoiceAnswer, string]("answer not found: " & id)
  let ans = resp.answers[id]
  if ans.answerKind != akChoice:
    return err[ChoiceAnswer, string]("answer '" & id & "' is not a choice")
  ok[ChoiceAnswer, string](ans.choiceAns)

proc score*(resp: SystemOneResponse; id: string): Result[ScoreAnswer, string] =
  if id notin resp.answers:
    return err[ScoreAnswer, string]("answer not found: " & id)
  let ans = resp.answers[id]
  if ans.answerKind != akScore:
    return err[ScoreAnswer, string]("answer '" & id & "' is not a score")
  ok[ScoreAnswer, string](ans.scoreAns)

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
