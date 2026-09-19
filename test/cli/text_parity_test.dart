import 'dart:io';

import 'package:shutter/src/cli/agent_text.dart';
import 'package:shutter/src/cli/manual_text.dart';
import 'package:test/test.dart';

void main() {
  test('agent_text.dart mirrors doc/agent.md byte for byte', () {
    expect(agentText, File('doc/agent.md').readAsStringSync());
  });

  test('manual_text.dart mirrors doc/manual.md byte for byte', () {
    expect(manualText, File('doc/manual.md').readAsStringSync());
  });
}
