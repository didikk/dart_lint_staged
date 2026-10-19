/// Matches current `dart format` output (Dart 3.x).
const kFormattedDart = '''const kTestMap = {'foo': 'bar'};
''';

const kUnFormattedDart = '''const kTestMap = {
      'foo': 'bar',
};
''';

const kInvalidDart = '''const kTestMap = {
      'foo': 'bar',
''';
