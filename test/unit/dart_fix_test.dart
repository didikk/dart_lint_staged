import 'dart:io';

import 'package:dart_lint_staged/src/dart_fix.dart';
import 'package:path/path.dart';
import 'package:test/test.dart';

const _unfixed = 'var x = "x";\n';
const _fixed = "var x = 'x';\n";

void main() {
  late Directory dir;
  String read(String name) => File(join(dir.path, name)).readAsStringSync();

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dart_fix_test');
    File(join(dir.path, 'pubspec.yaml'))
        .writeAsStringSync('name: fixture\nenvironment:\n  sdk: ^3.0.0\n');
    File(join(dir.path, 'analysis_options.yaml'))
        .writeAsStringSync('linter:\n  rules:\n    - prefer_single_quotes\n');
    for (var name in ['a', 'b', 'c']) {
      File(join(dir.path, 'lib', '$name.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync(_unfixed);
    }
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('fixes every file with one analyzer process', () async {
    var started = 0;
    final result = await dartFix(
      ['lib/a.dart', 'lib/b.dart', 'lib/c.dart'],
      workingDirectory: dir.path,
      start: (exe, args, {workingDirectory}) {
        started++;
        return Process.start(exe, args, workingDirectory: workingDirectory);
      },
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(started, 1);
    for (var name in ['a', 'b', 'c']) {
      expect(read('lib/$name.dart'), _fixed);
    }
  });

  test('leaves files outside the batch untouched', () async {
    final result = await dartFix(['lib/a.dart'], workingDirectory: dir.path);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(read('lib/a.dart'), _fixed);
    expect(read('lib/b.dart'), _unfixed);
    expect(read('lib/c.dart'), _unfixed);
  });

  test('fails when the analyzer does not answer', () async {
    final result = await dartFix(
      ['lib/a.dart'],
      workingDirectory: dir.path,
      start: (exe, args, {workingDirectory}) =>
          Process.start('dart', ['--bogus-flag']),
    );
    expect(result.exitCode, isNot(0));
    expect(read('lib/a.dart'), _unfixed);
  });
}
