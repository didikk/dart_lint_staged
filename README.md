# dart_lint_staged

[![CI](https://github.com/didikk/dart_lint_staged/actions/workflows/ci.yml/badge.svg)](https://github.com/didikk/dart_lint_staged/actions/workflows/ci.yml)

Run linters on git staged files for your Flutter and Dart projects.

This package is an **improved fork** of [`hyiso/lint_staged`](https://github.com/hyiso/lint_staged), aligned with the JavaScript [lint-staged](https://github.com/okonet/lint-staged) approach: staged files are **batched into each command** (not one process per file), and concurrency defaults to the number of CPU cores so large commits do not hang the machine.

## Improvements over the original

- **Batched commands** — e.g. `dart format a.dart b.dart …` in one process
- **Bounded concurrency** — default `--processes` = CPU count (no unbounded fan-out)
- Safer process pool (no post-run PID kill; iterative workers)

Config in `pubspec.yaml` still uses the `lint_staged:` key for drop-in compatibility.

## Why

Linting makes more sense when run before committing your code. By doing so you can ensure no errors go into the repository and enforce code style. But running a lint process on a whole project is slow, and linting results can be irrelevant. Ultimately you only want to lint files that will be committed.

## Installation and setup

1. Install *dart_lint_staged*:
   - `dart pub add --dev dart_lint_staged`
2. Set up the `pre-commit` git hook to run *dart_lint_staged*
   - [Husky](https://github.com/hyiso/husky) is a recommended choice for configuring git hooks
   - Read more about git hooks [here](https://git-scm.com/book/en/v2/Customizing-Git-Git-Hooks)
3. Configure tasks in `pubspec.yaml`:
   ```yaml
   lint_staged:
     'lib/**.dart': dart format && dart fix --apply
   ```
   - See [Configuration](#configuration) for more info

Don't forget to commit changes to `pubspec.yaml` and `.husky` to share this setup with your team!

## Changelog

See [CHANGELOG.md](https://github.com/didikk/dart_lint_staged/blob/main/CHANGELOG.md).

## Command line flags

```
❯ dart run dart_lint_staged --help
Usage: dart_lint_staged [options]

Options:
  --allow-empty                      allow empty commits when tasks revert all staged changes (default: false)
  --diff [string]                    override the default "--staged" flag of "git diff" to get list of files. Implies
                                     "--no-stash".
  --diff-filter [string]             override the default "--diff-filter=ACMR" flag of "git diff" to get list of files
  --no-stash                         disable the backup stash, and do not revert in case of errors
  --processes, -p [int]              maximum concurrent processes (default: number of CPU cores)
```

- **`--allow-empty`**: By default, when linter tasks undo all staged changes, dart_lint_staged will exit with an error and abort the commit. Use this flag to allow creating empty git commits.
- **`--diff`**: Override `--staged` with arbitrary revisions (e.g. `--diff="branch1...branch2"`). Implies `--no-stash`.
- **`--diff-filter`**: Override the default `ACMR` filter. See [git diff --diff-filter](https://git-scm.com/docs/git-diff#Documentation/git-diff.txt---diff-filterACDMRTUXB82308203).
- **`--no-stash`**: Disable the backup stash (and revert on error).
- **`--processes`**: Cap concurrent processes. Defaults to `Platform.numberOfProcessors`.

## Configuration

Configure in your `pubspec.yaml`:

```yaml
lint_staged:
  'lib/**.dart': your-cmd
```

This runs `your-cmd` with **all matching staged files** passed as arguments (chunked if the argv would exceed platform limits).

## Filtering files

Linter commands work on a subset of all staged files, defined by a _glob pattern_. dart_lint_staged uses [glob](https://github.com/dart-lang/glob) for matching.

### Exclude pattern: `!`

```yaml
lint_staged:
  'lib/**.dart': your-cmd
  '!lib/**.g.dart': your-cmd
```

This includes all `.dart` files but excludes `.g.dart` files.

## What commands are supported?

Any executables on your `$PATH` (for example `dart`, `flutter`).

`dart_lint_staged` uses `Process.run` to run commands. Pass arguments separated by spaces as you would in the shell.

## Running multiple commands in a sequence

Join commands with ` && `. They run sequentially; each receives the batched file list:

```yaml
lint_staged:
  'lib/**.dart': dart format && dart fix --apply
```

## Examples

In `.husky/pre-commit`:

```shell
#!/usr/bin/env sh
. "$(dirname "$0")/_/husky.sh"

dart run dart_lint_staged
```

_Note: do not pass file paths yourself — dart_lint_staged appends staged files for you._

### Format staged Dart files

```yaml
lint_staged:
  'lib/**.dart': dart format
```

### Apply fixes to staged Dart files

```yaml
lint_staged:
  'lib/**.dart': dart fix --apply
```

## Programmatic API

```dart
import 'package:dart_lint_staged/dart_lint_staged.dart';

final success = await lintStaged(
  allowEmpty: false,
  stash: true,
);
```

## Attribution

Based on [`lint_staged`](https://pub.dev/packages/lint_staged) by [hyiso](https://github.com/hyiso/lint_staged) (Apache-2.0), itself inspired by JS [lint-staged](https://github.com/okonet/lint-staged).

## License

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
