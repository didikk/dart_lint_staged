## 1.0.1

- **FIX**: `dart fix` runs once per staged file (it accepts only one path); previously multi-file commits failed with "Only one file or directory is expected."
- **DOCS**: pub.dev version badge; multiline (YAML list) command example

## 1.0.0

Initial release of **dart_lint_staged**, an improved fork of
[`hyiso/lint_staged`](https://github.com/hyiso/lint_staged).

- **FEAT**: Batch staged files into each command (JS lint-staged style) instead of one process per file
- **FEAT**: Default process pool size to CPU count; `--processes` still overrides
- **FIX**: Remove unsafe `Process.killPid` after `Process.run`
- **FIX**: Use iterative workers in the process pool (no deep recursion)
- **FIX**: Commands chained with `&&` run in order per file chunk instead of in parallel (no race between e.g. `dart fix` and `dart format`, also across globs matching the same file); a failing command stops the chain
- **FIX**: `--processes` rejects values below 1 (previously ran no commands and passed); empty commands in config are ignored
- **FIX**: A missing executable or other spawn error fails the task and restores the repo instead of crashing mid-run
- **FIX**: `MERGE_MSG` is restored after a revert
- **FIX**: `FileSystem.write`/`append` await the write
- **FIX**: Missing `pubspec.yaml` reports "no configuration" instead of throwing; repeated whitespace in commands no longer yields empty args
- **PERF**: `git status` skips untracked files; initial git reads run concurrently; files matched by several globs are staged once
- **CHORE**: Package renamed to `dart_lint_staged`; requires Dart SDK `^3.0.0`
- Config key is `dart_lint_staged:` in `pubspec.yaml`; legacy `lint_staged:` still read as fallback
