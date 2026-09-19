import 'dart:io';

import 'package:shutter/src/project/process_runner.dart';
import 'package:test/test.dart';

void main() {
  test('runProcess runs an executable', () async {
    final result = await runProcess(Platform.resolvedExecutable, ['--version']);
    expect(result.exitCode, 0);
  });
}
