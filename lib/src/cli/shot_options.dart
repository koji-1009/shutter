import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../engine/widget_shot.dart';
import '../project/project.dart';
import '../shutter_exception.dart';

/// The `--widget` expression with its `--import` files resolved to URIs:
/// `package:flutter/widgets.dart` first, then each import.
WidgetShot parseWidgetShot(
  Project project, {
  required String source,
  required List<String> imports,
  required (double, double)? size,
  required String workingDirectory,
}) => WidgetShot(
  source: source,
  imports: [
    'package:flutter/widgets.dart',
    for (final import in imports) _importUri(project, import, workingDirectory),
  ],
  size: size,
);

/// Parses option [name] as an integer ≥ 0, or throws a usage error.
int parseCount(ArgResults results, String name) {
  final raw = results.option(name)!;
  final value = int.tryParse(raw);
  if (value == null || value < 0) {
    throw ShutterException.usage(
      '--$name must be a whole number ≥ 0 (got "$raw").',
    );
  }
  return value;
}

/// Parses `--size` as `<width>x<height>` in logical pixels.
(double, double) parseSize(String raw) {
  final parts = raw.split('x');
  final values = [for (final part in parts) double.tryParse(part)];
  if (values case [final width?, final height?]
      when width > 0 && height > 0 && width.isFinite && height.isFinite) {
    return (width, height);
  }
  throw ShutterException.usage(
    '--size must be <width>x<height>, e.g. 390x844 (got "$raw").',
  );
}

String _importUri(Project project, String import, String workingDirectory) =>
    import.startsWith('package:')
    ? import
    : project.packageUri(
        libFile(
          project,
          import,
          workingDirectory: workingDirectory,
          what: '--import',
        ),
      );

/// Absolute path of [path], relative to [workingDirectory], which must be
/// a file under `lib/`. [what] names it in errors.
String libFile(
  Project project,
  String path, {
  required String workingDirectory,
  required String what,
}) {
  final resolved = p.normalize(p.join(workingDirectory, path));
  if (!File(resolved).existsSync()) {
    throw ShutterException.noInput('$what $path does not exist.');
  }
  if (!p.isWithin(project.libDir, resolved)) {
    throw ShutterException.usage('$what must be under lib/ ($path).');
  }
  return resolved;
}
