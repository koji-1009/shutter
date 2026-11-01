// Values built without `const`, so equal ones are not the same instance.
// ignore_for_file: prefer_const_constructors

import 'package:shutter/shutter.dart';
import 'package:test/test.dart';

/// [make] builds equal values on each call; each of [others] differs from
/// them in one field.
void valueType(Object Function() make, List<Object> others, String shown) {
  final a = make();
  final b = make();
  expect(identical(a, b), isFalse, reason: 'build values, not constants');
  expect(a, b);
  expect(a.hashCode, b.hashCode);
  expect({a, b}, hasLength(1));
  for (final other in others) {
    expect(a, isNot(other), reason: '$other');
  }
  expect('$a', shown);
}

void main() {
  test('inputs compare by value and print what they hold', () {
    var text = 'Save';
    String fresh() => text.substring(0);
    valueType(() => ShotTarget.text(fresh()), [
      ShotTarget.key(text),
      ShotTarget.text('Open'),
    ], 'text:Save');
    valueType(() => ShotAction.enter(ShotTarget.label(fresh()), 'Koji'), [
      ShotAction.enter(ShotTarget.label(text), 'Ko'),
      ShotAction.tap(ShotTarget.label(text)),
      ShotAction.enter(ShotTarget.key(text), 'Koji'),
    ], 'enter label:Save=Koji');
    text = 'lib/a.dart';
    valueType(() => PreviewFiles([fresh()]), [
      const PreviewFiles([]),
      const PreviewFiles(['lib/b.dart']),
      const PreviewFiles(['lib/a.dart', 'lib/b.dart']),
    ], 'PreviewFiles(files: [lib/a.dart])');
    valueType(
      () => WidgetExpression(
        'B()',
        imports: [fresh()],
        size: LogicalSize(200, 56.5),
      ),
      [
        const WidgetExpression('A()', imports: ['lib/a.dart']),
        const WidgetExpression(
          'B()',
          imports: ['lib/b.dart'],
          size: LogicalSize(200, 56.5),
        ),
        const WidgetExpression(
          'B()',
          imports: ['lib/a.dart'],
          size: WidgetSize.unbounded,
        ),
      ],
      'WidgetExpression(expression: B(), imports: [lib/a.dart], '
      'size: 200x56.5)',
    );
    valueType(() => PreviewCapture(), [
      const ScreenCapture(),
    ], 'PreviewCapture()');
    valueType(() => ScreenCapture(viewport: LogicalSize(390, 844)), [
      const ScreenCapture(),
      const PreviewCapture(),
    ], 'ScreenCapture(viewport: 390x844)');
    valueType(() => ScreenCapture(), [
      const ScreenCapture(viewport: LogicalSize(390, 844)),
    ], 'ScreenCapture()');
    valueType(() => Keyboard(336, tint: 0x809E9E9E), [
      const Keyboard(336),
      const Keyboard(300, tint: 0x809E9E9E),
    ], 'Keyboard(height: 336, tint: 0x809E9E9E)');
    expect('${Keyboard(336.5)}', 'Keyboard(height: 336.5)');
    valueType(() => LogicalSize(390, 844.5), [
      const LogicalSize(844.5, 390),
      WidgetSize.unbounded,
    ], '390x844.5');
    expect('${const LogicalSize(double.infinity, 1)}', 'Infinityx1');
    expect('${WidgetSize.unbounded}', 'unbounded');
  });

  test('results compare by value and print what they hold', () {
    var dir = '/app/runs/r1';
    String fresh() => dir.substring(0);
    ShotResult result(String png) => ShotResult(
      id: 'a.0',
      status: ShotStatus.ok,
      name: 'a',
      file: 'lib/a.dart',
      line: 2,
      size: LogicalSize(390, 844),
      brightness: 'dark',
      textScaleFactor: 2,
      png: png,
      error: 'e',
      at: 'lib/a.dart:2',
    );
    valueType(
      () => result('${fresh()}/a.0.png'),
      [
        for (final changed in [
          ShotResult(id: 'b.0', status: ShotStatus.ok, name: 'a'),
          result('/app/runs/r2/a.0.png'),
        ])
          changed,
        const ShotResult(id: 'a.0', status: ShotStatus.error, name: 'a'),
      ],
      'ShotResult(id: a.0, status: ok, name: a, file: lib/a.dart, line: 2, '
      'size: 390x844, brightness: dark, textScaleFactor: 2.0, '
      'png: /app/runs/r1/a.0.png, error: e, at: lib/a.dart:2)',
    );
    expect(
      '${const ShotResult(id: 'a.0', status: ShotStatus.error, name: 'a')}',
      'ShotResult(id: a.0, status: error, name: a)',
    );
    const shot = ShotResult(id: 'a.0', status: ShotStatus.ok, name: 'a');
    valueType(
      () => ShotRun(id: 'r1', dir: fresh(), shots: [shot]),
      [
        ShotRun(id: 'r2', dir: dir, shots: const [shot]),
        const ShotRun(id: 'r1', dir: '/app/runs/r2', shots: [shot]),
        ShotRun(id: 'r1', dir: dir, shots: const []),
      ],
      'ShotRun(id: r1, dir: /app/runs/r1, shots: '
      '[ShotResult(id: a.0, status: ok, name: a)])',
    );
    dir = '/app/runs/r0';
    valueType(
      () => PruneResult(removed: [fresh()], kept: const ['/app/runs/r1']),
      [
        const PruneResult(removed: [], kept: ['/app/runs/r1']),
        const PruneResult(removed: ['/app/runs/r0'], kept: []),
      ],
      'PruneResult(removed: [/app/runs/r0], kept: [/app/runs/r1])',
    );
  });

  test('progress events compare by value and print what they hold', () {
    var name = 'lib/a.dart';
    String fresh() => name.substring(0);
    valueType(() => ScanStarted([fresh()]), [
      const ScanStarted([]),
      const FontsDownloading(['lib/a.dart']),
    ], 'ScanStarted(files: [lib/a.dart])');
    valueType(() => RenderStarted(1), [
      const RenderStarted(2),
      const ShotRendered(1, 'a.0'),
    ], 'RenderStarted(round: 1)');
    name = 'a.0';
    valueType(() => ShotRendered(1, fresh()), [
      const ShotRendered(2, 'a.0'),
      const ShotRendered(1, 'b.0'),
    ], 'ShotRendered(round: 1, id: a.0)');
    name = 'Lato-Regular.ttf';
    valueType(() => FontsDownloading([fresh()]), [
      const FontsDownloading([]),
      const ScanStarted(['Lato-Regular.ttf']),
    ], 'FontsDownloading(fonts: [Lato-Regular.ttf])');
  });
}
