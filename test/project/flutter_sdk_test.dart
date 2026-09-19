import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shutter/src/project/flutter_sdk.dart';
import 'package:shutter/src/shutter_exception.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  test('locate prefers FLUTTER_ROOT', () {
    final sdk = FlutterSdk.locate(environment: {'FLUTTER_ROOT': '/sdk'});
    expect(sdk!.root, '/sdk');
  });

  test('locate falls back to a flutter executable on PATH, resolving '
      'symlinks', () {
    final sdk = createSdk();
    final bin = tempDir();
    Link(p.join(bin, 'flutter')).createSync(p.join(sdk, 'bin', 'flutter'));
    final found = FlutterSdk.locate(
      environment: {'FLUTTER_ROOT': '', 'PATH': ':/nonexistent:$bin'},
      isWindows: false,
    );
    expect(found!.root, sdk);
  });

  test('locate on Windows looks for flutter.bat with ; separators', () {
    final sdk = tempDir();
    writeFiles(sdk, {'bin/flutter.bat': '', 'packages/flutter/x': ''});
    final found = FlutterSdk.locate(
      environment: {'PATH': '/nonexistent;${p.join(sdk, 'bin')}'},
      isWindows: true,
    );
    expect(found!.root, sdk);
  });

  test('a flutter outside an SDK (a shim) is asked for its root', () {
    final shims = tempDir();
    writeFiles(shims, {'flutter': '#!/bin/sh'});
    FlutterSdk? locate(ProcessResult Function() answer) => FlutterSdk.locate(
      environment: {'PATH': shims},
      isWindows: false,
      runSync: (executable, arguments) {
        expect(executable, p.join(shims, 'flutter'));
        expect(arguments, ['--version', '--machine']);
        return answer();
      },
    );
    expect(
      locate(
        () => ProcessResult(0, 0, jsonEncode({'flutterRoot': '/real'}), ''),
      )!.root,
      '/real',
    );
    expect(locate(() => ProcessResult(0, 1, '', 'no')), isNull);
    expect(locate(() => ProcessResult(0, 0, '[]', '')), isNull);
    expect(locate(() => ProcessResult(0, 0, 'not json', '')), isNull);
    expect(locate(() => throw const ProcessException('flutter', [])), isNull);
  });

  test('locate returns null when nothing is found; require throws', () {
    expect(FlutterSdk.locate(environment: {}), isNull);
    expect(
      () => FlutterSdk.require(environment: {}),
      throwsA(
        isA<ShutterException>().having((e) => e.exitCode, 'exitCode', 69),
      ),
    );
    expect(FlutterSdk.require(environment: {'FLUTTER_ROOT': '/s'}).root, '/s');
  });

  test('executable and font cache paths', () {
    final sdk = FlutterSdk('/sdk');
    expect(sdk.executable(isWindows: false), p.join('/sdk', 'bin', 'flutter'));
    expect(
      sdk.executable(isWindows: true),
      p.join('/sdk', 'bin', 'flutter.bat'),
    );
    expect(sdk.executable(), endsWith(Platform.isWindows ? '.bat' : 'flutter'));
    expect(
      sdk.materialFontsDir,
      p.join('/sdk', 'bin', 'cache', 'artifacts', 'material_fonts'),
    );
  });

  test('version reads flutter.version.json', () {
    expect(FlutterSdk(createSdk()).version, '3.47.4');
    expect(FlutterSdk(createSdk(version: null)).version, isNull);
    final broken = createSdk(version: null);
    writeFiles(broken, {'bin/cache/flutter.version.json': '{'});
    expect(FlutterSdk(broken).version, isNull);
    final list = createSdk(version: null);
    writeFiles(list, {'bin/cache/flutter.version.json': '[]'});
    expect(FlutterSdk(list).version, isNull);
    final wrongType = createSdk(version: null);
    writeFiles(wrongType, {
      'bin/cache/flutter.version.json': '{"frameworkVersion": 3}',
    });
    expect(FlutterSdk(wrongType).version, isNull);
  });

  test('parseVersion and isAtLeast', () {
    expect(parseVersion('3.47.4-0.1.pre'), (3, 47, 4));
    expect(parseVersion('main'), isNull);
    expect(isAtLeast('3.47.0', (3, 47, 0)), isTrue);
    expect(isAtLeast('3.46.9', (3, 47, 0)), isFalse);
    expect(isAtLeast('4.0.0', (3, 47, 0)), isTrue);
    expect(isAtLeast('2.99.0', (3, 47, 0)), isFalse);
    expect(isAtLeast('3.48.0', (3, 47, 5)), isTrue);
    expect(isAtLeast('x', (3, 47, 0)), isFalse);
  });
}
