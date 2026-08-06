"""Formats .st files in place using tc3tools' STFormatter."""

from __future__ import annotations

import os
import sys
from pathlib import Path

from tc3tools.core.common import LocalFileSystem
from tc3tools.formatters.st_formatter import STFormatter, STSyntaxChecker, STToolService

# `bazel run` executes this binary with the runfiles tree as cwd, not the
# directory it was invoked from -- BUILD_WORKING_DIRECTORY is Bazel's own
# env var for recovering that, needed since callers (e.g. the fmt-st
# pre-commit hook) pass paths relative to their own invocation directory.
_INVOCATION_DIR = os.environ.get("BUILD_WORKING_DIRECTORY")


def usage() -> str:
    return """Usage: fmt_st.py [--check] [--format] <file.st>...

--check reports files that need formatting (exit 1) without writing them;
--format reformats files in place. This is about formatting only --
tc3tools' separate ST syntax linter isn't run here.

Wraps tc3tools.formatters.st_formatter.STToolService directly rather than
its CLI (tc3tools fmt-st) because that CLI's `input` argument only accepts a
single file or directory, not the list of individual files a pre-commit
hook passes.
"""


def main(argv: list[str]) -> int:
    check = "--check" in argv
    format_ = "--format" in argv
    if check and format_:
        print("error: --check and --format are mutually exclusive", file=sys.stderr)
        print(usage())
        return 1

    paths = [arg for arg in argv if arg not in ("--check", "--format")]
    if not paths:
        print(usage())
        return 1

    service = STToolService(LocalFileSystem(), STSyntaxChecker(), STFormatter())
    exit_code = 0
    inplace = format_ or not check
    for path in paths:
        resolved = Path(_INVOCATION_DIR, path) if _INVOCATION_DIR else Path(path)
        exit_code |= service.process(
            resolved, check=False, format_code=True, inplace=inplace
        )
    return exit_code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
