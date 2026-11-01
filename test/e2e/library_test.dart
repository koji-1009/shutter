@Tags(['e2e'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shutter/shutter.dart';
import 'package:test/test.dart';

import 'e2e_helpers.dart';

void main() {
  test('shot from Dart: the run, its shots, and progress as each shot '
      'renders', () async {
    final root = await exampleCopy();
    final events = <ShotProgress>[];
    final run = await shot(
      root,
      const PreviewFiles(['lib/preview/button_preview.dart']),
      onProgress: events.add,
    );
    expect(p.dirname(run.dir), p.join(root, '.dart_tool', 'shutter', 'runs'));
    expect(p.basename(run.dir), run.id);
    expect(run.shots, isNotEmpty);
    expect(run.hasErrors, isFalse);
    for (final result in run.shots) {
      expect(result.status, ShotStatus.ok, reason: result.error);
      expect(result.file, 'lib/preview/button_preview.dart');
      expect(File(result.png!).existsSync(), isTrue);
      expect(p.isWithin(run.dir, result.png!), isTrue);
    }
    expect(events.first.message, 'scanning lib/preview/button_preview.dart');
    expect(events[1], isA<RenderStarted>());
    expect(
      {
        for (final event in events)
          if (event is ShotRendered) event.id,
      },
      {for (final result in run.shots) result.id},
    );

    // A widget that does not compile is an error shot, not an exception.
    final broken = await shot(root, const WidgetExpression('Missing()'));
    expect(broken.hasErrors, isTrue);
    expect(broken.shots.single.error, contains('Missing'));

    // The two runs compared from Dart, a title drawn above each sheet.
    final compared = await diff(
      root,
      run.dir,
      broken.dir,
      composite: const DiffComposite(title: 'Button'),
    );
    expect(compared.hasChanges, isTrue);
    final removed = [
      for (final entry in compared.entries)
        if (entry.status == DiffStatus.removed) entry,
    ];
    expect(removed.map((e) => e.shot.id), {
      for (final result in run.shots) result.id,
    });
    for (final entry in removed) {
      expect(File(entry.compositePng!).existsSync(), isTrue);
    }

    await expectLater(
      shot(root, const PreviewFiles(['lib/preview/nope.dart'])),
      throwsA(
        isA<ShutterException>().having((e) => e.exitCode, 'exitCode', 66),
      ),
    );
  });
}
