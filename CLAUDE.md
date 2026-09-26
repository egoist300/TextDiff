# TextDiff

A PowerShell module that aligns two line lists (Myers), finds in-line changes, and renders console
lines and a self-contained side-by-side HTML. Published to the PowerShell Gallery. Usage, commands
and the release procedure are in `README.md`.

## Conventions not visible in code

- Target is Windows PowerShell 5.1 only. Run tests and lint in a fresh `powershell.exe -NoProfile`.
- One function per file, file name = function name. `Public/` is exported and must match
  `FunctionsToExport`; everything else goes in `Private/`. Every function has `tests/<Name>.Tests.ps1`.
  `tests/TextDiff.Module.Tests.ps1` enforces these.
- The module holds no console colors and no wording beyond the HTML labels. Callers decide colors and
  messages (for example the "N 行省略" line from `OmittedCount`). Keep it that way.
- Code comments are in Japanese and say why, not what changed.

## Versioning

Semantic versioning on the public surface (the three exported functions, their parameters and the
shape of what they return, and the HTML they produce):
- major: a caller has to change (removed or renamed parameter, changed return shape);
- minor: new parameter, new function, new optional key;
- patch: everything else.
A published version cannot be overwritten, so bump `ModuleVersion` and add the `CHANGELOG.md`
heading before tagging.

## Comment-based help

Every function, including test helpers and functions defined inside functions, has help that
documents every parameter. Public functions also have at least one `.EXAMPLE`.
`tests/CommentBasedHelp.Tests.ps1` enforces both.

## Case in string comparisons

State the rule at every comparison: `-ceq` / `-cne` / `-cmatch` for data, `-i` operators for
PowerShell's own names, `switch -CaseSensitive`, `Sort-Object -CaseSensitive`, and a
`StringComparison` for `StartsWith` / `EndsWith` / `IndexOf`. In tests use `Should -BeExactly` /
`-MatchExactly`.

## File encoding

`.ps1` `.psd1` `.psm1` are UTF-8 with exactly one BOM; `.md` `.yml` `.json` `.html` have no BOM;
LF everywhere (`.gitattributes` disables conversion). `tests/FileEncoding.Tests.ps1` checks this.
