import 'dart:io';

import 'package:ansi/ansi.dart';
import 'package:verbose/verbose.dart';

import 'chunk.dart';
import 'config.dart';
import 'context.dart';
import 'fs.dart';
import 'git.dart';
import 'group.dart';
import 'logging.dart';
import 'message.dart';
import 'processes_pool.dart';
import 'symbols.dart';
import 'workflow.dart';

final _verbose = Verbose('dart_lint_staged:run');

Future<Context> runAll({
  bool allowEmpty = false,
  List<String> diff = const [],
  String? diffFilter,
  bool stash = true,
  String? workingDirectory,
  int maxArgLength = 0,
  int? numOfProcesses,
}) async {
  final ctx = getInitialContext();
  final fs = FileSystem(workingDirectory);
  if (!await fs.exists('.git')) {
    ctx.output.add(kNotGitRepoMsg);
    ctx.errors.add(kGitRepoError);
    throw ctx;
  }
  final git = Git(
      diff: diff, diffFilter: diffFilter, workingDirectory: workingDirectory);

  /// Test whether we have any commits or not.
  /// Stashing must be disabled with no initial commit.
  final results = await Future.wait([git.lastCommit, git.stagedFiles]);
  final hasInitialCommit = (results[0] as String).isNotEmpty;

  /// dart_lint_staged will create a backup stash only when there's an initial commit,
  /// and when using the default list of staged files by default
  ctx.shouldBackup = hasInitialCommit && stash;
  if (!ctx.shouldBackup) {
    final reason = diff.isNotEmpty
        ? '`--diff` was used'
        : hasInitialCommit
            ? '`--no-stash` was used'
            : 'there\'s no initial commit yet';
    stdout.warn('Skipping backup because $reason.');
  }
  final stagedFiles = results[1] as List<String>;
  if (stagedFiles.isEmpty) {
    ctx.output.add(kNoStagedFilesMsg);
    return ctx;
  }
  final config = await loadConfig(workingDirectory: workingDirectory);
  if (config == null || config.isEmpty) {
    ctx.errors.add(kConfigNotFoundError);
    throw ctx;
  }
  final groups = groupFilesByConfig(config: config, files: stagedFiles);
  if (groups.isEmpty) {
    ctx.output.add(kNoStagedFilesMatchedMsg);
    return ctx;
  }
  final matchedFiles =
      groups.values.expand((element) => element.files).toSet().toList();
  final matchedFileChunks =
      chunkFiles(matchedFiles, maxArgLength: maxArgLength);
  final workflow = Workflow(
    fs: fs,
    ctx: ctx,
    git: git,
    allowEmpty: allowEmpty,
    matchedFileChunks: matchedFileChunks,
  );
  final spinner = Spinner();
  spinner.progress('Preparing dart_lint_staged...');
  await workflow.prepare();
  spinner.success('Prepared dart_lint_staged');
  if (ctx.hasPartiallyStagedFiles) {
    spinner.progress('Hide unstaged changes...');
    await workflow.hideUnstagedChanges();
    spinner.success('Hide unstaged changes');
  } else {
    spinner.skipped('Hide unstaged changes');
  }
  spinner.progress('Run tasks for staged files...');
  final poolSize = numOfProcesses ?? Platform.numberOfProcessors;
  final processesPool = ProcessesPool(size: poolSize);

  /// Caps concurrent task processes at `--processes`, across all jobs.
  final slots = Semaphore(poolSize);

  /// Runs [command] on [batch]; records the error and returns false on failure.
  /// [cancelled] is checked once a slot is free; a batch still queued behind a
  /// failure is skipped (counts as success, the failure is already recorded).
  Future<bool> runBatch(List<String> command, List<String> batch,
      {bool Function()? cancelled}) async {
    final script = command.join(' ');
    final messsages = ['$script ${batch.join(' ')}'];
    try {
      await slots.acquire();
      final ProcessResult result;
      try {
        if (cancelled?.call() ?? false) return true;
        result = await ProcessTask(
          command.first,
          [...command.skip(1), ...batch],
          workingDirectory: workingDirectory,
        ).run();
      } finally {
        slots.release();
      }
      if (result.stderr.toString().trim().isNotEmpty) {
        messsages.add(red(result.stderr.toString().trim()));
      }
      if (result.stdout.toString().trim().isNotEmpty) {
        messsages.add(result.stdout.toString().trim());
      }
      _verbose(messsages.join('\n'));
      if (result.exitCode == 0) return true;
    } on Exception catch (e) {
      messsages.add(red(e is ProcessException ? e.message : '$e'));
    }
    ctx.output.add(messsages.join('\n'));
    ctx.errors.add(kTaskError);
    return false;
  }

  Future<void> runCommands(
      List<List<String>> commands, List<String> files) async {
    for (var command in commands) {
      // `dart fix` accepts a single path, so it runs once per file. Each run
      // only edits its own file, so run them in parallel; `slots` bounds them.
      if (command.length > 1 && command[0] == 'dart' && command[1] == 'fix') {
        var failed = false;
        await Future.wait([
          for (var f in files)
            () async {
              if (!await runBatch(command, [f], cancelled: () => failed)) {
                failed = true;
              }
            }()
        ]);
        if (failed) return;
      } else if (!await runBatch(command, files)) {
        return;
      }
    }
  }

  // Groups that match the same file must not edit it concurrently, so they run
  // one after another in a single job. Other groups run their chunks in parallel.
  for (var related in _groupsSharingFiles(groups.values.toList())) {
    final steps = [
      for (var group in related)
        (
          commands: group.scripts
              .map((script) => script.trim().split(RegExp(r'\s+')))
              .toList(),
          chunks: chunkFiles(group.files, maxArgLength: maxArgLength),
        ),
    ];
    if (steps.length > 1) {
      processesPool.addJob(() async {
        for (var step in steps) {
          for (var files in step.chunks) {
            await runCommands(step.commands, files);
          }
        }
      });
    } else {
      for (var files in steps.single.chunks) {
        processesPool.addJob(() => runCommands(steps.single.commands, files));
      }
    }
  }

  await processesPool.start();
  processesPool.close();

  spinner.success('Run tasks for staged files');
  if (!applyModifationsSkipped(ctx)) {
    spinner.progress('Apply modifications...');
    await workflow.applyModifications();
    spinner.success('Apply modifications');
  } else {
    spinner.skipped('Apply modifications');
  }
  if (ctx.hasPartiallyStagedFiles && !restoreUnstagedChangesSkipped(ctx)) {
    spinner.progress('Restore unstaged changes...');
    await workflow.resotreUnstagedChanges();
    spinner.success('Restore unstaged changes');
  } else {
    spinner.skipped('Restore unstaged changes');
  }
  if (restoreOriginalStateEnabled(ctx) && !restoreOriginalStateSkipped(ctx)) {
    spinner.progress('Revert because of errors...');
    await workflow.restoreOriginState();
    spinner.success('Revert because of errors');
  } else {
    spinner.skipped('Revert because of errors');
  }
  if (cleanupEnabled(ctx) && !cleanupSkipped(ctx)) {
    spinner.progress('Cleanup temporary files...');
    await workflow.cleanup();
    spinner.success('Cleanup temporary files');
  } else {
    spinner.skipped('Cleanup temporary files');
  }
  if (ctx.errors.isNotEmpty) {
    throw ctx;
  }
  return ctx;
}

/// Partitions [groups] into sets connected by shared files, keeping config order.
List<List<Group>> _groupsSharingFiles(List<Group> groups) {
  final parent = List.generate(groups.length, (i) => i);
  int find(int i) => parent[i] == i ? i : parent[i] = find(parent[i]);
  final owner = <String, int>{};
  for (var i = 0; i < groups.length; i++) {
    for (var file in groups[i].files) {
      parent[find(i)] = find(owner.putIfAbsent(file, () => i));
    }
  }
  final sets = <int, List<Group>>{};
  for (var i = 0; i < groups.length; i++) {
    sets.putIfAbsent(find(i), () => []).add(groups[i]);
  }
  return sets.values.toList();
}
