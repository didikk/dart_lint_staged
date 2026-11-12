import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

typedef ProcessStarter = Future<Process> Function(
    String executable, List<String> arguments,
    {String? workingDirectory});

Future<Process> _start(String executable, List<String> arguments,
        {String? workingDirectory}) =>
    Process.start(executable, arguments, workingDirectory: workingDirectory);

/// Applies `dart fix` to [files] with a single analysis server.
///
/// `dart fix` accepts only one path and analyzes the whole package per call,
/// so a process per file multiplies memory and CPU. Instead ask one server for
/// `edit.bulkFixes` on all [files] and write the edits ourselves; edits for any
/// file outside [files] are ignored.
Future<ProcessResult> dartFix(
  List<String> files, {
  List<String> codes = const [],
  String? workingDirectory,
  ProcessStarter start = _start,
}) async {
  final root = workingDirectory ?? Directory.current.path;
  // Resolved path -> path as given, so edits match even through symlinks.
  final included = {
    for (var f in files)
      File(p.normalize(p.join(root, f))).resolveSymbolicLinksSync(): f
  };
  final server = await start('dart',
      ['language-server', '--protocol=analyzer', '--suppress-analytics'],
      workingDirectory: workingDirectory);
  final stderrText = server.stderr.transform(utf8.decoder).join();
  Map<String, dynamic>? reply;
  await for (var line in server.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())) {
    final Object? message;
    try {
      message = jsonDecode(line);
    } on FormatException {
      continue;
    }
    if (message is! Map<String, dynamic>) continue;
    if (message['event'] == 'server.connected') {
      server.stdin.writeln(jsonEncode({
        'id': '1',
        'method': 'edit.bulkFixes',
        'params': {
          'included': included.keys.toList(),
          if (codes.isNotEmpty) 'codes': codes,
        },
      }));
    } else if (message['id'] == '1') {
      reply = message;
      server.stdin
          .writeln(jsonEncode({'id': '2', 'method': 'server.shutdown'}));
    } else if (message['id'] == '2') {
      break;
    }
  }
  await server.stdin.close();
  final exitCode = await server.exitCode;
  final stderr = await stderrText;
  final result = reply?['result'];
  if (result is! Map<String, dynamic>) {
    final error = reply?['error'];
    return ProcessResult(server.pid, exitCode == 0 ? 1 : exitCode, '',
        [if (error != null) jsonEncode(error), stderr].join('\n'));
  }
  final fixed = <String>[];
  for (var fileEdit in (result['edits'] as List).cast<Map>()) {
    final path = fileEdit['file'] as String;
    if (!included.containsKey(path)) continue;
    final file = File(path);
    var content = await file.readAsString();
    // Edits come sorted by descending offset, so earlier offsets stay valid.
    for (var edit in (fileEdit['edits'] as List).cast<Map>()) {
      final offset = edit['offset'] as int;
      content = content.replaceRange(offset, offset + (edit['length'] as int),
          edit['replacement'] as String);
    }
    await file.writeAsString(content);
    fixed.add(included[path]!);
  }
  return ProcessResult(server.pid, 0,
      fixed.isEmpty ? 'Nothing to fix!' : 'Fixed ${fixed.join(' ')}', stderr);
}
