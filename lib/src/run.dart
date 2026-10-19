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
  final hasInitialCommit = (await git.lastCommit).isNotEmpty;

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
  final stagedFiles = await git.stagedFiles;
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
      groups.values.expand((element) => element.files).toList();
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
  for (var group in groups.values) {
    for (var script in group.scripts) {
      final args = script.split(' ');
      final exe = args.removeAt(0);
      final fileChunks = chunkFiles(group.files, maxArgLength: maxArgLength);
      for (var files in fileChunks) {
        processesPool.addTask(
          ProcessTask(
            exe,
            [...args, ...files],
            workingDirectory: workingDirectory,
            onCompleted: (result) {
              final messsages = ['$script ${files.join(' ')}'];
              if (result.stderr.toString().trim().isNotEmpty) {
                messsages.add(red(result.stderr.toString().trim()));
              }
              if (result.stdout.toString().trim().isNotEmpty) {
                messsages.add(result.stdout.toString().trim());
              }
              _verbose(messsages.join('\n'));
              if (result.exitCode != 0) {
                ctx.output.add(messsages.join('\n'));
                ctx.errors.add(kTaskError);
              }
            },
          ),
        );
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
