import 'dart:io';

import 'package:shutter/src/entry_point.dart';
import 'package:shutter/src/version.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  tearDown(() => exitCode = 0);

  test('--version prints the version', () async {
    exitCode = 3;
    final result = await captureIO(() => runApp(['--version']));
    expect(result.stdout, 'shutter $shutterVersion\n');
    expect(exitCode, 0);
  });

  test('a successful command, and --help, set exit 0', () async {
    for (final args in [
      ['agent'],
      ['--help'],
    ]) {
      exitCode = 3;
      await captureIO(() => runApp(args));
      expect(exitCode, 0, reason: '$args');
    }
  });

  test('usage errors exit 64', () async {
    final result = await captureIO(() => runApp(['nope']));
    expect(exitCode, 64);
    expect(result.stderr, contains('Could not find a command named "nope"'));
  });

  test('ShutterException exits with its code', () async {
    final result = await captureIO(() => runApp(['diff', 'x', 'y']));
    expect(exitCode, 66);
    expect(result.stderr, startsWith('shutter: no run "x"'));
  });

  test('the zone error handler sets exit 70', () async {
    final result = await captureIO(
      () => handleUncaughtZoneError(StateError('x'), StackTrace.empty),
    );
    expect(exitCode, 70);
    expect(result.stderr, startsWith('Unhandled error: Bad state: x'));
  });

  test('a closed pipe is not an error; the exit code stands', () async {
    for (final error in [
      const FileSystemException('writeFrom failed', '', OSError('', 32)),
      const SocketException('write failed', osError: OSError('', 32)),
    ]) {
      exitCode = 1;
      final result = await captureIO(
        () => handleUncaughtZoneError(error, StackTrace.empty),
      );
      expect((exitCode, result.stderr), (1, ''), reason: '$error');
    }
    await captureIO(
      () => handleUncaughtZoneError(
        const FileSystemException('x', '', OSError('', 13)),
        StackTrace.empty,
      ),
    );
    expect(exitCode, 70);
  });

  test('--version after a subcommand is not the version flag', () async {
    await captureIO(() => runApp(['shot', '--version']));
    expect(exitCode, 64);
  });
}
