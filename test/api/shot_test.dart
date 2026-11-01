import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shutter/shutter.dart';
import 'package:shutter/src/api/shot.dart' show shotIn;
import 'package:shutter/src/cli/context.dart';
import 'package:shutter/src/run/manifest.dart';
import 'package:test/test.dart';

import '../cli/fakes.dart';
import '../helpers.dart';

/// [shotIn] with [shot]'s defaults.
Future<ShotRun> shootIn(
  ShutterContext context,
  ShotSubject subject, {
  Duration settle = const Duration(milliseconds: 300),
  String? shell,
  List<ShotAction> actions = const [],
  ShotCapture capture = const PreviewCapture(),
  Keyboard? keyboard,
  Map<String, String> networkImages = const {},
  ShotPlatform platform = ShotPlatform.android,
  bool semantics = false,
  void Function(ShotProgress event)? onProgress,
}) => shotIn(
  context,
  subject,
  settle: settle,
  shell: shell,
  actions: actions,
  capture: capture,
  keyboard: keyboard,
  networkImages: networkImages,
  platform: platform,
  semantics: semantics,
  onProgress: onProgress,
);

Matcher usageError(String message) => isA<ShutterException>()
    .having((e) => e.exitCode, 'exitCode', 64)
    .having((e) => e.message, 'message', contains(message));

void main() {
  test(
    'returns the run directory and each shot, with absolute PNG paths',
    () async {
      final root = createProject(
        files: {'test/images/a.png': 'a', 'lib/ui/b.dart': ''},
      );
      final engine = FakeEngine(const [
        Shot(
          id: 'b.0',
          status: ShotStatus.error,
          name: 'b',
          file: 'lib/b.dart',
          line: 3,
          error: 'boom',
          at: 'lib/ui/b.dart:9:3',
        ),
        Shot(
          id: 'a.0',
          status: ShotStatus.ok,
          name: 'a',
          file: 'lib/a.dart',
          line: 2,
          size: (390, 844.5),
          brightness: 'dark',
          textScaleFactor: 2,
          png: 'a.0.png',
        ),
      ]);
      final run = await shootIn(
        fakeContext(root, engine: engine),
        const WidgetExpression(
          'B()',
          imports: ['lib/ui/b.dart', 'package:flutter/material.dart'],
          size: LogicalSize(200, 56.5),
        ),
        settle: const Duration(milliseconds: 700),
        actions: const [
          ShotAction.tap(ShotTarget.text('Open')),
          ShotAction.enter(ShotTarget.label('Email'), 'a@example.com'),
          ShotAction.hover(ShotTarget.type('DropdownButton<String>')),
        ],
        capture: const ScreenCapture(viewport: LogicalSize(390, 844)),
        keyboard: const Keyboard(336, tint: 0xFF9E9E9E),
        networkImages: {'https://example.com/a.png': 'test/images/a.png'},
        platform: ShotPlatform.ios,
      );
      final dir = p.join(root, '.dart_tool', 'shutter', 'runs', run.id);
      expect(
        run,
        ShotRun(
          id: '20260918T101530Z',
          dir: dir,
          shots: [
            ShotResult(
              id: 'a.0',
              status: ShotStatus.ok,
              name: 'a',
              file: 'lib/a.dart',
              line: 2,
              size: const LogicalSize(390, 844.5),
              brightness: 'dark',
              textScaleFactor: 2,
              png: p.join(dir, 'a.0.png'),
            ),
            const ShotResult(
              id: 'b.0',
              status: ShotStatus.error,
              name: 'b',
              file: 'lib/b.dart',
              line: 3,
              error: 'boom',
              at: 'lib/ui/b.dart:9:3',
            ),
          ],
        ),
      );
      expect(run.hasErrors, isTrue);
      expect(File(run.shots.first.png!).existsSync(), isTrue);

      final request = engine.requests.single;
      expect(request.widget!.source, 'B()');
      expect(request.widget!.imports, [
        'package:flutter/widgets.dart',
        'package:app/ui/b.dart',
        'package:flutter/material.dart',
      ]);
      expect(
        (request.widget!.size, request.widget!.unbounded),
        ((200.0, 56.5), false),
      );
      expect(request.settleMs, 700);
      expect(request.actions.map((a) => a.label), [
        'tap text:Open',
        'enter label:Email=a@example.com',
        'hover type:DropdownButton<String>',
      ]);
      expect((request.screen, request.viewport), (true, (390.0, 844.0)));
      expect((request.keyboard, request.keyboardTint), (336.0, 0xFF9E9E9E));
      expect(request.networkImages, {
        'https://example.com/a.png': p.join(root, 'test', 'images', 'a.png'),
      });
      expect((request.platform, request.semantics), (ShotPlatform.ios, false));
      expect(RunManifest.read(dir).setup.platform, ShotPlatform.ios);
    },
  );

  test('paths are relative to the project directory given', () async {
    final root = createProject(files: {'lib/ui/b.dart': ''});
    final engine = FakeEngine(const []);
    await shootIn(
      fakeContext(p.join(root, 'lib'), engine: engine),
      const WidgetExpression('B()', imports: ['ui/b.dart']),
    );
    expect(
      engine.requests.single.widget!.imports.last,
      'package:app/ui/b.dart',
    );
  });

  test('preview files: scanned with progress, the semantics tree, an '
      'unbounded widget', () async {
    const preview =
        "import 'package:flutter/widget_previews.dart';\n"
        "import 'package:flutter/widgets.dart';\n"
        "@Preview()\nWidget a() => const Text('');";
    final root = createProject(
      resolvable: true,
      files: {'lib/preview/a.dart': preview},
    );
    final engine = FakeEngine(const []);
    final events = <ShotProgress>[];
    final run = await shootIn(
      fakeContext(root, engine: engine),
      const PreviewFiles(['lib/preview/a.dart']),
      capture: const ScreenCapture(),
      keyboard: const Keyboard(300),
      semantics: true,
      onProgress: events.add,
    );
    expect(run.shots, isEmpty);
    expect(run.hasErrors, isFalse);
    expect(events, [
      const ScanStarted(['lib/preview/a.dart']),
    ]);
    final request = engine.requests.single;
    expect(request.libraries.single.file, 'lib/preview/a.dart');
    expect(request.onProgress, isNotNull);
    expect((request.screen, request.viewport), (true, null));
    expect((request.keyboard, request.keyboardTint), (300.0, null));
    expect(request.semantics, isTrue);

    final unbounded = FakeEngine(const []);
    await shootIn(
      fakeContext(root, engine: unbounded),
      const WidgetExpression('B()', size: WidgetSize.unbounded),
    );
    final widget = unbounded.requests.single.widget!;
    expect((widget.size, widget.unbounded), (null, true));
    expect(unbounded.requests.single.screen, isFalse);
  });

  test('arguments that do not fit together throw before the project is '
      'touched', () async {
    final root = createProject();
    Future<ShotRun> run({
      ShotSubject subject = const WidgetExpression('A()'),
      Duration settle = Duration.zero,
      List<ShotAction> actions = const [],
      ShotCapture capture = const PreviewCapture(),
      Keyboard? keyboard,
      bool semantics = false,
    }) => shootIn(
      fakeContext(root),
      subject,
      settle: settle,
      actions: actions,
      capture: capture,
      keyboard: keyboard,
      semantics: semantics,
    );
    await expectLater(
      run(settle: const Duration(milliseconds: -1)),
      throwsA(usageError('settle must not be negative')),
    );
    await expectLater(
      run(subject: const PreviewFiles([])),
      throwsA(usageError('PreviewFiles names no file.')),
    );
    await expectLater(
      run(actions: const [ShotAction.tap(ShotTarget.key(''))]),
      throwsA(usageError('tap key:: the action names no widget.')),
    );
    for (final actions in const [
      [ShotAction.press(ShotTarget.key('a')), ShotAction.focus(.key('b'))],
      [ShotAction.press(ShotTarget.key('a')), ShotAction.tap(.key('b'))],
    ]) {
      await expectLater(
        run(actions: actions),
        throwsA(usageError('at most one press, hover, or focus action, last')),
      );
    }
    for (final size in const [
      LogicalSize(0, 1),
      LogicalSize(1, -1),
      LogicalSize(double.infinity, 1),
      LogicalSize(1, double.nan),
    ]) {
      await expectLater(
        run(capture: ScreenCapture(viewport: size)),
        throwsA(usageError('viewport must be > 0 and finite')),
      );
      await expectLater(
        run(subject: WidgetExpression('A()', size: size)),
        throwsA(usageError('widget size must be > 0 and finite')),
      );
    }
    for (final height in [0.0, -1.0, double.infinity, double.nan]) {
      await expectLater(
        run(keyboard: Keyboard(height)),
        throwsA(usageError('keyboard height must be a logical size > 0')),
      );
    }
    for (final tint in [-1, 0x100000000]) {
      await expectLater(
        run(keyboard: Keyboard(300, tint: tint)),
        throwsA(usageError('keyboard tint must be an ARGB color')),
      );
    }
    await expectLater(
      run(keyboard: const Keyboard(300, tint: 0), semantics: true),
      throwsA(usageError('semantics draws no keyboard tint')),
    );
    expect(
      Directory(p.join(root, '.dart_tool', 'shutter')).existsSync(),
      isFalse,
    );
  });

  test('a run that cannot be shot throws with its sysexits code', () async {
    final root = createProject(flutterTest: false);
    await expectLater(
      shot(root, const WidgetExpression('A()')),
      throwsA(
        isA<ShutterException>()
            .having((e) => e.exitCode, 'exitCode', 78)
            .having(
              (e) => e.message,
              'message',
              contains('flutter_test is not in dev_dependencies'),
            ),
      ),
    );
    await expectLater(
      shootIn(
        fakeContext(createProject()),
        const WidgetExpression('A()'),
        networkImages: {'https://example.com/a.png': 'nope.png'},
      ),
      throwsA(
        isA<ShutterException>().having((e) => e.exitCode, 'exitCode', 66),
      ),
    );
    await expectLater(
      shootIn(
        fakeContext(createProject(), environment: const {}),
        const WidgetExpression('A()'),
      ),
      throwsA(
        isA<ShutterException>().having((e) => e.exitCode, 'exitCode', 69),
      ),
    );
  });

  test('progress messages', () {
    expect(
      const ScanStarted(['lib/a.dart', 'lib/b.dart']).message,
      'scanning lib/a.dart, lib/b.dart',
    );
    expect(const RenderStarted(1).message, 'rendering');
    expect(const RenderStarted(2).message, 'rendering again with added fonts');
    expect(const ShotRendered(1, 'a.0').message, 'rendered a.0');
    expect(
      const FontsDownloading(['Lato-Regular.ttf']).message,
      'downloading Lato-Regular.ttf',
    );
  });

  test('actions: their target and whether they hold through the capture', () {
    const enter = ShotAction.enter(ShotTarget.key('name'), 'Koji');
    expect(
      (enter.kind, enter.by, enter.value, enter.text),
      (ActionKind.enter, TargetKind.key, 'name', 'Koji'),
    );
    expect(
      [
        for (final action in const [
          ShotAction.tap(ShotTarget.text('a')),
          enter,
          ShotAction.press(ShotTarget.label('a')),
          ShotAction.hover(ShotTarget.type('A')),
          ShotAction.focus(ShotTarget.key('a')),
        ])
          action.held,
      ],
      [false, false, true, true, true],
    );
  });
}
