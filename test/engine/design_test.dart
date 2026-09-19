import 'dart:convert';

import 'package:shutter/src/engine/design.dart';
import 'package:shutter/src/project/flutter_sdk.dart';
import 'package:shutter/src/project/project.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// A project depending on [dependencies], with [resolved] packages in its
/// package config.
Project project({
  List<String> dependencies = const [],
  List<String> resolved = const [],
}) {
  final root = createProject();
  writeFiles(root, {
    'pubspec.yaml': [
      'name: app',
      if (dependencies.isNotEmpty) 'dependencies:',
      for (final d in dependencies) '  $d: any',
    ].join('\n'),
    if (resolved.isNotEmpty)
      '.dart_tool/package_config.json': jsonEncode({
        'packages': [
          for (final name in resolved) {'name': name, 'rootUri': '../../$name'},
        ],
      }),
  });
  return Project.load(root);
}

FlutterSdk sdk({bool legacy = true}) {
  final root = createSdk();
  if (legacy) {
    writeFiles(root, {
      'packages/flutter/lib/material.dart': '',
      'packages/flutter/lib/cupertino.dart': '',
    });
  }
  return FlutterSdk(root);
}

void main() {
  test('the SDK copies back the default Material shell', () {
    final design = DesignSupport.detect(project(), sdk());
    expect(design.available, [DesignLibrary.material, DesignLibrary.cupertino]);
    expect(design.shell, DesignLibrary.material);
  });

  test('a direct material_ui dependency takes the shell', () {
    final design = DesignSupport.detect(
      project(
        dependencies: ['material_ui', 'cupertino_ui'],
        resolved: ['material_ui', 'cupertino_ui'],
      ),
      sdk(),
    );
    expect(design.available, DesignLibrary.values);
    expect(design.shell, DesignLibrary.materialUi);
  });

  test('a direct cupertino_ui dependency takes the shell; transitive or '
      'unresolved ones do not', () {
    expect(
      DesignSupport.detect(
        project(dependencies: ['cupertino_ui'], resolved: ['cupertino_ui']),
        sdk(legacy: false),
      ).shell,
      DesignLibrary.cupertinoUi,
    );
    final transitive = DesignSupport.detect(
      project(resolved: ['material_ui']),
      sdk(legacy: false),
    );
    expect(transitive.available, [DesignLibrary.materialUi]);
    expect(transitive.shell, isNull);
    expect(
      DesignSupport.detect(project(dependencies: ['material_ui']), sdk()).shell,
      DesignLibrary.material,
    );
  });

  test('without design libraries: a WidgetsApp shell, no theme fallback', () {
    final source = designSource(
      const DesignSupport(available: [], shell: null),
    );
    expect(
      source,
      contains('Widget defaultShell(Widget child) => WidgetsApp('),
    );
    expect(source, isNot(contains(' as \$')));
    expect(source, isNot(contains('TextStyle f(')));
    expect(source, contains('  return result;'));
  });

  test('theme fallbacks: Cupertino innermost', () {
    final source = designSource(
      const DesignSupport(
        available: [DesignLibrary.material, DesignLibrary.cupertinoUi],
        shell: DesignLibrary.material,
      ),
    );
    expect(
      source,
      contains("import 'package:flutter/material.dart' as \$material;"),
    );
    expect(
      source,
      contains(
        "import 'package:cupertino_ui/cupertino_ui.dart' as \$cupertinoUi;",
      ),
    );
    expect(source, contains('\$material.Material(child: child)'));
    expect(source, contains('TextStyle f('));
    final cupertino = source.indexOf('\$cupertinoUi.CupertinoTheme(');
    final material = source.indexOf('\$material.Theme(');
    expect(cupertino, greaterThan(0));
    expect(material, greaterThan(cupertino));

    final cupertinoShell = designSource(
      const DesignSupport(
        available: [DesignLibrary.cupertino],
        shell: DesignLibrary.cupertino,
      ),
    );
    expect(cupertinoShell, contains('\$cupertino.CupertinoApp('));
  });
}
