## Internal submodule example. Import with ``import jev_nim_client/submodule``.

type
  Submodule* = object
    name*: string

proc initSubmodule*(): Submodule =
  Submodule(name: "Anonymous")
