const kConfigFormatFix = '''dart_lint_staged:
  'lib/**.dart': dart format
''';

const kConfigFormatFixWithIgnore = '''dart_lint_staged:
  'lib/**.dart': dart format
  '!lib/**.g.dart': dart format
''';

const kConfigFormatExit = '''dart_lint_staged:
  'lib/**.dart': dart format --set-exit-if-changed
''';

const kConfigFormatAndFix = '''dart_lint_staged:
  'lib/**.dart': dart format && dart fix --apply
''';
