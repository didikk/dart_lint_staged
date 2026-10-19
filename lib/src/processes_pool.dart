import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

typedef OnCompleted = void Function(ProcessResult result);

class ProcessTask {
  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String>? environment;
  final bool includeParentEnvironment;
  final bool runInShell;
  final Encoding? stdoutEncoding;
  final Encoding? stderrEncoding;
  final OnCompleted? onCompleted;

  /// The copy of the parameter of Process.run()
  const ProcessTask(
    this.executable,
    this.arguments, {
    this.workingDirectory,
    this.environment,
    this.includeParentEnvironment = true,
    this.runInShell = false,
    this.stdoutEncoding = systemEncoding,
    this.stderrEncoding = systemEncoding,
    this.onCompleted,
  });

  Future<ProcessResult> run() async {
    return Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
      runInShell: runInShell,
      stdoutEncoding: stdoutEncoding,
      stderrEncoding: stderrEncoding,
    );
  }
}

typedef PoolJob = Future<void> Function();

class ProcessesPool {
  final int size;
  final Queue<PoolJob> _jobs = Queue();
  bool isStarted = false;

  int get tasksNumber => _jobs.length;

  ProcessesPool({
    required this.size,
  }) : assert(size > 0);

  void addAll({
    List<ProcessTask> tasks = const [],
  }) {
    tasks.forEach(addTask);
  }

  void addTask(ProcessTask task) {
    addJob(() async => task.onCompleted?.call(await task.run()));
  }

  /// Queue an arbitrary async job, e.g. several commands that must run in order.
  void addJob(PoolJob job) {
    _jobs.add(job);
  }

  Future<void> start() async {
    if (isStarted) {
      throw Exception('You have already started');
    }
    isStarted = true;
    try {
      final workerCount = size < _jobs.length ? size : _jobs.length;
      await Future.wait(List.generate(workerCount, (_) => _runWorker()));
    } finally {
      isStarted = false;
    }
  }

  Future<void> _runWorker() async {
    while (_jobs.isNotEmpty) {
      await _jobs.removeFirst()();
    }
  }

  void close() {
    _jobs.clear();
  }
}
