# dart_lint_staged example

Minimal setup: format and fix staged Dart files before each commit.

1. Add the package:

   ```sh
   dart pub add --dev dart_lint_staged
   ```

2. Configure commands in your `pubspec.yaml`:

   ```yaml
   dart_lint_staged:
     'lib/**.dart': dart format && dart fix --apply
   ```

3. Run it in your `pre-commit` hook (for example with [Husky](https://github.com/hyiso/husky), in `.husky/pre-commit`):

   ```sh
   #!/usr/bin/env sh
   . "$(dirname "$0")/_/husky.sh"

   dart run dart_lint_staged
   ```

Stage a `.dart` file under `lib/` and commit. The staged files are formatted and fixed, and the changes are added to the commit.

Do not pass file paths in the config. `dart_lint_staged` appends the staged files for you.

See the [main README](https://github.com/didikk/dart_lint_staged#readme) for all options.
