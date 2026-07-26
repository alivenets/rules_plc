# simple_2

`mathlib`: an `st_library` with a `cc_test` depending on it, exercising the
compiled ST code directly through `st_library`'s exported `CcInfo`.

`st_double`/`doubler_app`: an `st_library` (`st_double.st`) and an
`st_binary` (`doubler_app.st`'s `PROGRAM doubler_app`) that depends on it,
colocated.

`st_cycle`: a `PROGRAM` (`st_cycle.st`, the cyclically-executed PLC POU,
with persistent state across calls) as an `st_binary`'s `program`:
`st_binary` generates the `FUNCTION main` entry point that instantiates and
calls it.
