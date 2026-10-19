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

class ProcessEntity {
  final ProcessTask task;
  final Future<ProcessResult> process;
  const ProcessEntity({
    required this.task,
    required this.process,
  });
}

class ProcessesPool {
  final int size;
  final Queue<ProcessTask> _tasks = Queue();
  final List<ProcessEntity?> _processes = [];
  bool isStarted = false;

  int get tasksNumber => _tasks.length;

  ProcessesPool({
    required this.size,
  }) : assert(size > 0);

  void addAll({
    List<ProcessTask> tasks = const [],
  }) {
    _tasks.addAll(tasks);
  }

  void addTask(ProcessTask task) {
    _tasks.add(task);
  }

  Future<void> start({
    OnCompleted? onCompleted,
  }) async {
    if (isStarted) {
      throw Exception('You have already started');
    }
    isStarted = true;
    final workerCount = size < _tasks.length ? size : _tasks.length;
    if (workerCount == 0) {
      isStarted = false;
      return;
    }
    _processes.addAll(List.filled(workerCount, null));
    await Future.wait(List.generate(workerCount, (int index) {
      return _runWorker(
        index: index,
        onCompleted: onCompleted,
      );
    }));
    isStarted = false;
  }

  Future<void> _runWorker({
    required int index,
    OnCompleted? onCompleted,
  }) async {
    while (_tasks.isNotEmpty) {
      final ProcessTask task = _tasks.removeFirst();
      final Future<ProcessResult> process = task.run();
      _processes[index] = ProcessEntity(process: process, task: task);
      final ProcessResult result = await process;
      _processes[index] = null;
      (onCompleted ?? task.onCompleted)?.call(result);
    }
  }

  void close() {
    _tasks.clear();
    _processes.clear();
  }
}
