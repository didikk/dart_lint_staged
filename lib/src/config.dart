import 'dart:io';

import 'package:path/path.dart';
import 'package:verbose/verbose.dart';
import 'package:yaml/yaml.dart';

final _verbose = Verbose('dart_lint_staged:config');

Future<Map<String, List<String>>?> loadConfig({
  String? workingDirectory,
}) async {
  final pubspecPath =
      join(workingDirectory ?? Directory.current.path, 'pubspec.yaml');
  final pubspec = File(pubspecPath);
  if (!pubspec.existsSync()) return null;
  final yaml = loadYaml(pubspec.readAsStringSync());
  final map =
      yaml is Map ? (yaml['dart_lint_staged'] ?? yaml['lint_staged']) : null;
  if (map is! Map) {
    return null;
  }
  _verbose('Found config: $map');
  final config = <String, List<String>>{};
  for (var entry in map.entries) {
    final value = entry.value;
    if (value is String) {
      config[entry.key] = _commands(value.split('&&'));
    } else if (value is List) {
      config[entry.key] = _commands(value);
    }
  }
  return config;
}

/// Trimmed, non-empty commands.
List<String> _commands(Iterable<Object?> raw) =>
    raw.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toList();
