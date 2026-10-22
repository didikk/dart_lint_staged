import 'dart:io';

import 'package:dart_lint_staged/src/processes_pool.dart';
import 'package:test/test.dart';

void main() {
  group('ProcessesPool', () {
    const size = 4;
    const second = 2;
    const command = 'sleep';
    final task = ProcessTask(command, ['$second']);

    test('should be able to pass size parameter', () {
      final pool = ProcessesPool(size: size);
      expect(pool.size, size);
    });

    test('should be able to add one task', () {
      final pool = ProcessesPool(size: size);
      pool.addTask(task);
      expect(pool.tasksNumber, 1);
    });

    test('should be able to add multiple task', () {
      final tasks = List.filled(Platform.numberOfProcessors, task);
      final pool = ProcessesPool(size: size);
      pool.addAll(tasks: tasks);
      expect(pool.tasksNumber, tasks.length);
    });

    test('should run concurrently up to size', () async {
      final tasks = List.filled(Platform.numberOfProcessors, task);
      final pool = ProcessesPool(size: Platform.numberOfProcessors);
      pool.addAll(tasks: tasks);
      final stopwatch = Stopwatch()..start();
      await pool.start();
      stopwatch.stop();
      expect(stopwatch.elapsed.inSeconds, lessThan(second * 2));
    });

    test('should limit running tasks to provided size', () async {
      final tasks = List.filled(Platform.numberOfProcessors, task);
      final pool = ProcessesPool(size: size);
      pool.addAll(tasks: tasks);
      final stopwatch = Stopwatch()..start();
      await pool.start();
      stopwatch.stop();
      // size=4 workers; ceil(n/4)*2s should complete with a small timing slack
      expect(
        stopwatch.elapsed.inSeconds,
        lessThanOrEqualTo(
          ((Platform.numberOfProcessors + size - 1) ~/ size) * second + 1,
        ),
      );
    });

    test('should drain many tasks iteratively without stack overflow',
        () async {
      final tasks = List.generate(
        50,
        (_) => ProcessTask('sleep', ['0']),
      );
      final pool = ProcessesPool(size: 2);
      pool.addAll(tasks: tasks);
      await pool.start();
      expect(pool.tasksNumber, 0);
    });

    test('addJob never exceeds size concurrent jobs', () async {
      var running = 0;
      var peak = 0;
      final pool = ProcessesPool(size: 2);
      for (var i = 0; i < 6; i++) {
        pool.addJob(() async {
          peak = ++running > peak ? running : peak;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          running--;
        });
      }
      await pool.start();
      expect(peak, 2);
    });
  });

  group('Semaphore', () {
    test('never lets more than size holders run at once', () async {
      final slots = Semaphore(2);
      var running = 0;
      var peak = 0;
      await Future.wait([
        for (var i = 0; i < 6; i++)
          () async {
            await slots.acquire();
            peak = ++running > peak ? running : peak;
            await Future<void>.delayed(const Duration(milliseconds: 20));
            running--;
            slots.release();
          }()
      ]);
      expect(peak, 2);
      expect(running, 0);
    });
  });
}
