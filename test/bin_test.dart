import 'dart:convert';
import 'dart:io';

import 'package:shutter/src/version.dart';
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

/// `bin/shutter.dart` in a process of its own: what the in-memory tests
/// cannot see, such as the exit code reaching the OS and stdout being a
/// pipe.
Future<TestProcess> shutter(List<String> args) => TestProcess.start(
  Platform.resolvedExecutable,
  ['bin/shutter.dart', ...args],
);

void main() {
  test('--version prints to stdout and exits 0', () async {
    final process = await shutter(['--version']);
    await expectLater(process.stdout, emits('shutter $packageVersion'));
    await process.shouldExit(0);
  });

  test('an argument a command rejects prints its usage to stderr, exit '
      '64', () async {
    final process = await shutter(['shot', '--size', '1x1']);
    await expectLater(
      process.stderr,
      emitsThrough('shutter: --import and --size need --widget.'),
    );
    await expectLater(
      process.stderr,
      emitsThrough(
        'Usage: shutter shot <preview-file>... | shutter shot --widget <expression>',
      ),
    );
    await expectLater(process.stdout, emitsDone);
    await process.shouldExit(64);
  });

  test('a reader that closes the pipe early leaves no error', () async {
    final process = await Process.start(Platform.resolvedExecutable, [
      'bin/shutter.dart',
      'manual',
    ]);
    // Closed before the output is written, as `| grep -q` or `| head`
    // close it once they have read enough.
    await process.stdout.listen(null).cancel();
    final stderr = process.stderr.transform(utf8.decoder).join();
    expect(await process.exitCode, 0);
    expect(await stderr, isEmpty);
  });
}
