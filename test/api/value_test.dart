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
    expect(
      '${WidgetExpression('A()')}',
      'WidgetExpression(expression: A(), imports: [])',
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
    valueType(() => SafeAreaInsets(top: 59, bottom: 34.5), [
      const SafeAreaInsets(top: 59),
      const SafeAreaInsets(bottom: 34.5),
    ], 'SafeAreaInsets(top: 59, bottom: 34.5)');
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

  test('diff arguments and results compare by value and print what they '
      'hold', () {
    var title = 'Search';
    String fresh() => title.substring(0);
    valueType(() => DiffComposite(title: fresh()), [
      const DiffComposite(),
      const DiffComposite(direction: CompositeDirection.vertical, title: 'x'),
      const DiffComposite(title: 'Find'),
    ], 'DiffComposite(direction: auto, title: Search)');
    expect('${const DiffComposite()}', 'DiffComposite(direction: auto)');
    title = 'lib/preview/shell.dart';
    valueType(() => ShotFile(path: fresh(), sha256: 'abc'), [
      const ShotFile(path: 'lib/preview/shell.dart', sha256: 'abd'),
      const ShotFile(path: 'shell.dart', sha256: 'abc'),
    ], 'ShotFile(path: lib/preview/shell.dart, sha256: abc)');
    title = 'tap text:Open';
    ShotSetup setup({
      String action = 'tap text:Open',
      String url = 'https://example.com/a.png',
    }) => ShotSetup(
      shell: ShotFile(path: 'shell.dart', sha256: 'a'),
      actions: [action],
      capture: ScreenCapture(viewport: LogicalSize(390, 844)),
      keyboard: Keyboard(336),
      networkImages: {url: ShotFile(path: 'a.png', sha256: 'b')},
      semantics: true,
      platform: ShotPlatform.ios,
      pixelRatio: 2.625,
      safeArea: SafeAreaInsets(top: 59, bottom: 34),
      brightness: ShotBrightness.dark,
      textScale: 1.3,
    );
    valueType(
      () => setup(action: fresh()),
      [
        const ShotSetup(),
        setup(action: 'tap text:Close'),
        setup(url: 'https://example.com/b.png'),
      ],
      'ShotSetup(shell: ShotFile(path: shell.dart, sha256: a), '
      'actions: [tap text:Open], '
      'capture: ScreenCapture(viewport: 390x844), '
      'keyboard: Keyboard(height: 336), '
      'networkImages: {https://example.com/a.png: '
      'ShotFile(path: a.png, sha256: b)}, '
      'semantics: true, platform: ios, pixelRatio: 2.625, '
      'safeArea: SafeAreaInsets(top: 59, bottom: 34), brightness: dark, '
      'textScale: 1.3)',
    );
    expect(
      '${const ShotSetup()}',
      'ShotSetup(actions: [], capture: PreviewCapture(), networkImages: {}, '
          'semantics: false, platform: android, pixelRatio: 2, '
          'brightness: light, textScale: 1)',
    );
    expect(const ShotSetup(pixelRatio: 3), isNot(const ShotSetup()));
    expect(
      const ShotSetup(brightness: ShotBrightness.dark),
      isNot(const ShotSetup()),
    );
    expect(const ShotSetup(textScale: 2), isNot(const ShotSetup()));
    title = '/app/runs/r2/a.0.png';
    const shot = ShotResult(id: 'a.0', status: ShotStatus.ok, name: 'a');
    ShotDiffEntry entry(String png) => ShotDiffEntry(
      status: DiffStatus.changed,
      shot: shot,
      diffRatio: 0.25,
      beforeSize: LogicalSize(2, 2),
      beforePng: '/app/runs/r1/a.0.png',
      afterPng: png,
      diffPng: '/app/diffs/d/a.0.png',
      compositePng: '/app/diffs/d/a.0-composite.png',
    );
    valueType(
      () => entry(fresh()),
      [
        entry('/app/runs/r3/a.0.png'),
        const ShotDiffEntry(status: DiffStatus.unchanged, shot: shot),
      ],
      'ShotDiffEntry(status: changed, '
      'shot: ShotResult(id: a.0, status: ok, name: a), diffRatio: 0.25, '
      'beforeSize: 2x2, beforePng: /app/runs/r1/a.0.png, '
      'afterPng: /app/runs/r2/a.0.png, diffPng: /app/diffs/d/a.0.png, '
      'compositePng: /app/diffs/d/a.0-composite.png)',
    );
    title = '/app/runs/r2';
    const unchanged = ShotDiffEntry(status: DiffStatus.unchanged, shot: shot);
    ShotDiff result({
      String after = '/app/runs/r2',
      List<ShotDiffEntry> entries = const [unchanged],
      List<String> warnings = const ['w'],
    }) => ShotDiff(
      before: '/app/runs/r1',
      after: after,
      beforeSetup: const ShotSetup(),
      afterSetup: const ShotSetup(platform: ShotPlatform.ios),
      dir: '/app/diffs/d',
      entries: entries,
      warnings: warnings,
    );
    valueType(
      () => result(after: fresh()),
      [
        result(after: '/app/runs/r3'),
        result(entries: const []),
        result(warnings: const []),
      ],
      'ShotDiff(before: /app/runs/r1, after: /app/runs/r2, '
      'beforeSetup: ${const ShotSetup()}, '
      'afterSetup: ${const ShotSetup(platform: ShotPlatform.ios)}, '
      'dir: /app/diffs/d, entries: [$unchanged], warnings: [w])',
    );
    expect(
      '${const ShotDiff(before: 'a', after: 'b', beforeSetup: ShotSetup(), afterSetup: ShotSetup(), entries: [])}',
      'ShotDiff(before: a, after: b, beforeSetup: ${const ShotSetup()}, '
          'afterSetup: ${const ShotSetup()}, entries: [], warnings: [])',
    );
  });

  test('doctor checks compare by value and print what they hold', () {
    var message = 'font cache missing';
    String fresh() => message.substring(0);
    valueType(
      () =>
          DoctorCheck(CheckLevel.warn, fresh(), hint: 'run `flutter precache`'),
      [
        DoctorCheck(CheckLevel.fail, message, hint: 'run `flutter precache`'),
        const DoctorCheck(CheckLevel.warn, 'x', hint: 'run `flutter precache`'),
        DoctorCheck(CheckLevel.warn, message),
      ],
      'DoctorCheck(level: warn, message: font cache missing, '
      'hint: run `flutter precache`)',
    );
    message = 'project app';
    expect(
      '${DoctorCheck(CheckLevel.ok, fresh())}',
      'DoctorCheck(level: ok, message: project app)',
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
