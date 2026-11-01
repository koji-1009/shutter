import 'dart:io';

import 'package:shutter/src/project/process_runner.dart';
import 'package:test/test.dart';

void main() {
  test(
    'runProcess runs an executable, handing over stdout line by line',
    () async {
      final lines = <String>[];
      final result = await runProcess(Platform.resolvedExecutable, [
        '--version',
      ], onStdoutLine: lines.add);
      expect(result.exitCode, 0);
      expect(lines, isNotEmpty);
      expect(result.stdout, '${lines.join('\n')}\n');
      final quiet = await runProcess(Platform.resolvedExecutable, [
        '--version',
      ]);
      expect(quiet.stdout, result.stdout);
    },
  );
}
