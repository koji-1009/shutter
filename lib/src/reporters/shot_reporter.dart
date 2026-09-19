import 'dart:io';

import 'package:path/path.dart' as p;

import '../run/manifest.dart';
import 'format.dart';
import 'yaml_scalar.dart';

/// Writes the outcome of `shutter shot` for the run in [dir]: YAML
/// starting with `# shutter ai-report v1`, errors first, absolute paths.
void reportShots(RunManifest manifest, String dir, IOSink sink) {
  final errors = [
    for (final s in manifest.shots)
      if (s.status == ShotStatus.error) s,
  ];
  final oks = [
    for (final s in manifest.shots)
      if (s.status == ShotStatus.ok) s,
  ];
  final body = StringBuffer()
    ..writeln('# shutter ai-report v1')
    ..writeln('run: ${yamlScalar(dir)}')
    ..writeln('shell: ${formatShell(manifest.shell)}')
    ..writeln('summary: {error: ${errors.length}, ok: ${oks.length}}')
    ..writeln(listHeader('shots', errors.length + oks.length));
  for (final shot in [...errors, ...oks]) {
    writeEntryHead(body, shot.status.name, shot);
    if (shot.png case final png?) {
      body.writeln('    png: ${yamlScalar(p.join(dir, png))}');
    }
    writeError(body, shot);
  }
  sink.write(body);
}
