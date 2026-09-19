import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shutter/src/cli/context.dart';
import 'package:shutter/src/engine/engine.dart';
import 'package:shutter/src/run/manifest.dart';

import '../helpers.dart';

/// Engine returning [shots], writing a PNG for each shot naming one.
class FakeEngine implements Engine {
  FakeEngine(this.shots);

  final List<Shot> shots;
  final requests = <CaptureRequest>[];

  @override
  Future<List<Shot>> capture(CaptureRequest request) async {
    requests.add(request);
    for (final shot in shots) {
      if (shot.png case final png?) {
        File(p.join(request.runDir, png)).writeAsBytesSync(pngBytes);
      }
    }
    return shots;
  }
}

final pngBytes = png(4, 4);

/// A context on [root] with a fake SDK and [engine].
ShutterContext fakeContext(
  String root, {
  Engine? engine,
  String? sdk,
  Map<String, String>? environment,
}) {
  final sdkRoot = sdk ?? createSdk();
  return ShutterContext(
    workingDirectory: root,
    clock: () => DateTime.utc(2026, 9, 18, 10, 15, 30),
    environment: environment ?? {'FLUTTER_ROOT': sdkRoot},
    engineFactory: (sdk) => engine ?? FakeEngine(const []),
  );
}
