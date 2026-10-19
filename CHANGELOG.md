## 1.0.0

Initial release of **dart_lint_staged**, an improved fork of
[`hyiso/lint_staged`](https://github.com/hyiso/lint_staged).

- **FEAT**: Batch staged files into each command (JS lint-staged style) instead of one process per file
- **FEAT**: Default process pool size to CPU count; `--processes` still overrides
- **FIX**: Remove unsafe `Process.killPid` after `Process.run`
- **FIX**: Use iterative workers in the process pool (no deep recursion)
- **CHORE**: Package renamed to `dart_lint_staged`; requires Dart SDK `^3.0.0`
- Config key remains `lint_staged:` in `pubspec.yaml` for drop-in compatibility
