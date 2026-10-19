# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`dart_lint_staged`: Dart port of JS lint-staged (fork of `hyiso/lint_staged`). Runs configured commands on git-staged files, as a pre-commit hook. Config lives under the `lint_staged:` key in the consumer's `pubspec.yaml` (glob → command, `!glob` excludes, ` && ` chains commands). Each command gets matched files appended as args in batched invocations.

## Commands

```sh
dart pub get
dart format --output=none --set-exit-if-changed .   # CI format check
dart analyze                                        # CI lint (package:lints/recommended)
dart test                                           # all tests (CI)
dart test test/unit/chunk_test.dart                 # single file
dart test -n "name substring"                       # single test by name
dart run dart_lint_staged --help                    # run the CLI (bin/dart_lint_staged.dart)
```

Pre-commit for this repo itself is husky (`.husky/`) running the tool on its own `lint_staged:` config in `pubspec.yaml`.

## Architecture

`bin/dart_lint_staged.dart` parses flags → `lib/dart_lint_staged.dart` (`lintStaged()` public API) → `runAll()` in `lib/src/run.dart`, which orchestrates everything:

1. `git.dart` — wraps `git` CLI (staged files, partially staged files via `status -z -uno`, stashes, gitdir). Handles worktrees/submodules.
2. `config.dart` + `group.dart` — load `pubspec.yaml` config; `groupFilesByConfig` matches staged files via `glob`, then applies `!` exclusions.
3. `chunk.dart` — splits file lists to stay under argv length limits.
4. `workflow.dart` — port of JS lint-staged's git state machine: `prepare` (backup stash + patch of unstaged changes in `.git/dart_lint_staged_unstaged.patch`), `hideUnstagedChanges`, `applyModifications` (re-add task edits), `resotreUnstagedChanges` (sic), `restoreOriginState` on error, `cleanup`. Also saves/restores merge state (MERGE_HEAD etc.).
5. `processes_pool.dart` — bounded worker pool (`--processes`, default CPU count, must be >= 1) running async jobs (`addJob`; `addTask` wraps a `ProcessTask`). `run.dart` queues one job per (group, file chunk) that runs the group's commands in order and stops at the first failure (`&&` semantics). Groups sharing any file (`_groupsSharingFiles`) are merged into one sequential job so two chains never edit a file concurrently.
6. `context.dart` + `symbols.dart` + `message.dart` — shared `Context` (errors/output/flags) and error symbols; `run.dart` uses the `*Skipped`/`*Enabled` predicates in `context.dart` to decide which workflow steps run. `runAll` throws the `Context` on failure.
7. `logging.dart` — `Spinner` and output formatting.

Gotchas: commands are split on whitespace and run without a shell, so no quoting/pipes/globs inside a command; `config.dart` splits string values on `&&` and drops empty commands. Spawn errors (e.g. missing executable) are recorded as `kTaskError` so the normal revert path runs. Debug logging uses `package:verbose` (namespaces like `dart_lint_staged:run`).

## Tests

- `test/unit/` — pure unit tests (chunking, batching, context, git, pool).
- `test/integration/` — spin up real temp git repos via `IntegrationProject` in `test/integration/utils.dart` (requires `git` on PATH); fixtures in `__fixtures__/`. Scenarios mirror JS lint-staged (partial staging, merge conflicts, worktrees, submodules, amend, file resurrection).
