import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:shutter/src/cli/context.dart';
import 'package:shutter/src/cli/io_sinks.dart';
import 'package:shutter/src/entry_point.dart';
import 'package:test/test.dart';

/// A temporary directory removed after the current test.
String tempDir() {
  final dir = Directory.systemTemp.createTempSync('shutter_test_');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir.resolveSymbolicLinksSync();
}

/// Writes [files] (relative path → content) under [root].
void writeFiles(String root, Map<String, String> files) {
  for (final MapEntry(key: path, value: content) in files.entries) {
    File(p.join(root, path))
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }
}

/// A Flutter-app-shaped project (`name: app`, `publish_to: none`,
/// `flutter_test` dev dependency) holding [files]. With [resolvable], it
/// also has a package config resolving `package:app` and a stub
/// `package:flutter` (see [flutterStub]), so the analyzer can resolve it.
String createProject({
  Map<String, String> files = const {},
  String name = 'app',
  bool app = true,
  bool flutterTest = true,
  bool resolvable = false,
}) {
  final root = tempDir();
  writeFiles(root, {
    'pubspec.yaml': [
      'name: $name',
      if (app) 'publish_to: none',
      if (flutterTest) 'dev_dependencies:\n  flutter_test:\n    sdk: flutter',
    ].join('\n'),
    if (resolvable) ...{
      for (final MapEntry(:key, :value) in flutterStub.entries)
        'flutter_stub/lib/$key': value,
      '.dart_tool/package_config.json': jsonEncode({
        'configVersion': 2,
        'packages': [
          for (final (package, rootUri) in [
            (name, '../'),
            ('flutter', '../flutter_stub/'),
          ])
            {
              'name': package,
              'rootUri': rootUri,
              'packageUri': 'lib/',
              'languageVersion': '3.10',
            },
        ],
      }),
    },
    ...files,
  });
  return root;
}

/// The parts of `package:flutter` previews in tests refer to. `Preview`
/// and `MultiPreview` live in the library the scanner recognises them by.
const flutterStub = {
  'widgets.dart': '''
class Widget {
  const Widget();
}

class Text extends Widget {
  const Text(this.data);
  final String data;
}

class Size {
  const Size(this.width, this.height);
  final double width;
  final double height;
}

enum Brightness { light, dark }
''',
  'material.dart': '''
import 'widgets.dart';

class Badge extends Widget {
  const Badge();
}
''',
  'widget_previews.dart': "export 'src/widget_previews/widget_previews.dart';",
  'src/widget_previews/widget_previews.dart': '''
import '../../widgets.dart';

class Preview {
  const Preview({this.name, this.size, this.brightness, this.wrapper});
  final String? name;
  final Size? size;
  final Brightness? brightness;
  final Widget Function(Widget)? wrapper;
}

abstract class MultiPreview {
  const MultiPreview();
  List<Preview> get previews;
}
''',
};

/// The Dart SDK running the tests.
final String dartSdk = p.dirname(p.dirname(Platform.resolvedExecutable));

/// A directory shaped like a Flutter SDK: version file, font cache, and
/// `bin/cache/dart-sdk` linking to the Dart SDK running the tests.
String createSdk({String? version = '3.47.4', bool fonts = true}) {
  final root = tempDir();
  writeFiles(root, {
    'bin/flutter': '',
    'packages/flutter/pubspec.yaml': 'name: flutter',
    if (version != null)
      'bin/cache/flutter.version.json': jsonEncode({
        'frameworkVersion': version,
      }),
    if (fonts) 'bin/cache/artifacts/material_fonts/Roboto-Regular.ttf': '',
  });
  Link(p.join(root, 'bin', 'cache', 'dart-sdk'))
      .createSync(dartSdk, recursive: true);
  return root;
}

/// PNG bytes of a [width]×[height] image filled with [rgba].
Uint8List png(int width, int height, [List<int> rgba = const [0, 0, 0, 255]]) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(rgba[0], rgba[1], rgba[2], rgba[3]));
  return img.encodePng(image);
}

/// Output of one CLI invocation.
typedef CliResult = ({int? exitCode, String stdout, String stderr});

/// Runs [args] through [body] with [ShutterIO] captured.
Future<({T value, String stdout, String stderr})> captureIO<T>(
  FutureOr<T> Function() body,
) async {
  final outCtl = StreamController<List<int>>();
  final errCtl = StreamController<List<int>>();
  final outBuf = BytesBuilder();
  final errBuf = BytesBuilder();
  final drainOut = outCtl.stream.forEach(outBuf.add);
  final drainErr = errCtl.stream.forEach(errBuf.add);
  final outSink = IOSink(outCtl.sink);
  final errSink = IOSink(errCtl.sink);
  ShutterIO.stdoutSink = outSink;
  ShutterIO.stderrSink = errSink;
  try {
    final value = await body();
    await outSink.close();
    await errSink.close();
    await drainOut;
    await drainErr;
    return (
      value: value,
      stdout: utf8.decode(outBuf.toBytes()),
      stderr: utf8.decode(errBuf.toBytes()),
    );
  } finally {
    ShutterIO.stdoutSink = stdout;
    ShutterIO.stderrSink = stderr;
    if (!outCtl.isClosed) await outCtl.close();
    if (!errCtl.isClosed) await errCtl.close();
  }
}

/// Runs the CLI with [args] against [context].
Future<CliResult> runCli(List<String> args, ShutterContext context) async {
  final result = await captureIO(() => runShutter(args, context));
  return (exitCode: result.value, stdout: result.stdout, stderr: result.stderr);
}

/// Text written to an [IOSink] by [write].
Future<String> collect(void Function(IOSink sink) write) async {
  final controller = StreamController<List<int>>();
  final buffer = BytesBuilder();
  final done = controller.stream.forEach(buffer.add);
  final sink = IOSink(controller.sink);
  try {
    write(sink);
    await sink.close();
    await done;
    return utf8.decode(buffer.toBytes());
  } finally {
    if (!controller.isClosed) await controller.close();
  }
}
