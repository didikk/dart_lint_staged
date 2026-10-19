import 'package:dart_lint_staged/src/chunk.dart';
import 'package:test/test.dart';

/// Verifies JS lint-staged-style batching: many files become few argv chunks.
void main() {
  group('batched file chunks for tasks', () {
    test('all files stay in one chunk when maxArgLength is 0', () {
      final files = List.generate(20, (i) => 'lib/file_$i.dart');
      final chunks = chunkFiles(files, maxArgLength: 0);
      expect(chunks, hasLength(1));
      expect(chunks.first, hasLength(20));
    });

    test('many files split into few chunks when maxArgLength is small', () {
      final files = List.generate(10, (i) => 'lib/file_$i.dart');
      final chunks = chunkFiles(files, maxArgLength: 30);
      expect(chunks.length, greaterThan(1));
      expect(chunks.length, lessThan(files.length));
      expect(chunks.expand((c) => c).toList(), files);
    });
  });
}
