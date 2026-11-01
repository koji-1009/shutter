import 'dart:io';

import 'format.dart';
import 'yaml_scalar.dart';

/// Writes the outcome of `shutter prune`: YAML starting with
/// `# shutter ai-report v1`, the run directories [removed] and [kept],
/// oldest first.
void reportPrune({
  required List<String> removed,
  required List<String> kept,
  required IOSink sink,
}) {
  final body = StringBuffer()..writeln('# shutter ai-report v1');
  for (final (key, dirs) in [('removed', removed), ('kept', kept)]) {
    body.writeln(listHeader(key, dirs.length));
    for (final dir in dirs) {
      body.writeln('  - ${yamlScalar(dir)}');
    }
  }
  sink.write(body);
}
