const kConfigFormatFix = '''lint_staged:
  'lib/**.dart': dart format
''';

const kConfigFormatFixWithIgnore = '''lint_staged:
  'lib/**.dart': dart format
  '!lib/**.g.dart': dart format
''';

const kConfigFormatExit = '''lint_staged:
  'lib/**.dart': dart format --set-exit-if-changed
''';
