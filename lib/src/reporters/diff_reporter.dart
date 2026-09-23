import 'dart:io';

import 'package:path/path.dart' as p;

import '../diff/run_diff.dart';
import 'format.dart';
import 'yaml_scalar.dart';

/// Writes the outcome of `shutter diff`: YAML starting with
/// `# shutter ai-report v1`, in the order to look at the entries, with
/// absolute paths. [dir] holds the diff images (`--images`), else null.
void reportDiff(RunDiff diff, String? dir, IOSink sink) {
  final summary = [
    for (final MapEntry(:key, :value) in diff.summary.entries)
      '${key.name}: $value',
  ].join(', ');
  final body = StringBuffer()..writeln('# shutter ai-report v1');
  if (dir != null) body.writeln('diff: ${yamlScalar(dir)}');
  body
    ..writeln('before: ${yamlScalar(diff.before)}')
    ..writeln('after: ${yamlScalar(diff.after)}');
  // Only when the runs were shot in different shells, which changes
  // every image without any widget changing.
  if (diff.beforeShell != diff.afterShell) {
    body
      ..writeln('shell:')
      ..writeln('  before: ${formatShell(diff.beforeShell)}')
      ..writeln('  after: ${formatShell(diff.afterShell)}');
  }
  // Likewise the actions and what was captured: pressing a button, or
  // capturing the screen, changes the image without the widget changing.
  final (before, after) = (diff.beforeSetup, diff.afterSetup);
  for (final (key, a, b) in [
    ('actions', formatActions(before.actions), formatActions(after.actions)),
    ('capture', formatCapture(before.screen), formatCapture(after.screen)),
    (
      'viewport',
      formatViewport(before.viewport),
      formatViewport(after.viewport),
    ),
    (
      'keyboard',
      formatKeyboard(before.keyboard),
      formatKeyboard(after.keyboard),
    ),
  ]) {
    if (a != b) {
      body
        ..writeln('$key:')
        ..writeln('  before: $a')
        ..writeln('  after: $b');
    }
  }
  body
    ..writeln('summary: {$summary}')
    ..writeln(listHeader('entries', diff.entries.length));
  for (final entry in diff.entries) {
    writeEntryHead(body, entry.status.name, entry.shot);
    if (entry.beforeSize case final size?) {
      body.writeln('    before_size: ${formatSize(size)}');
    }
    if (entry.diffRatio case final ratio?) {
      // Significant digits, so a change of a few pixels never reads 0.
      body.writeln(
        '    diff_ratio: ${double.parse(ratio.toStringAsPrecision(4))}',
      );
    }
    writeError(body, entry.shot);
    for (final (key, base, name) in [
      ('before', diff.before, entry.beforePng),
      ('after', diff.after, entry.afterPng),
      ('diff', dir, entry.diffPng),
    ]) {
      if (base != null && name != null) {
        body.writeln('    $key: ${yamlScalar(p.join(base, name))}');
      }
    }
  }
  sink.write(body);
}
