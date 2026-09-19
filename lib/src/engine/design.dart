import 'dart:io';

import 'package:path/path.dart' as p;

import '../project/flutter_sdk.dart';
import '../project/project.dart';
import 'generator.dart' show generatedHeader;

/// A design library the generated test can build shells and theme
/// fallbacks with. The Flutter SDK's own copies are being replaced by the
/// `material_ui` and `cupertino_ui` packages; each is used while present.
enum DesignLibrary(
  final String uri, {

  /// Material (`Theme`, `MaterialApp`) rather than Cupertino.
  required final bool isMaterial,

  /// The pub package providing it; null for the Flutter SDK's copy.
  final String? package,
}) {
  material('package:flutter/material.dart', isMaterial: true),
  cupertino('package:flutter/cupertino.dart', isMaterial: false),
  materialUi(
    'package:material_ui/material_ui.dart',
    isMaterial: true,
    package: 'material_ui',
  ),
  cupertinoUi(
    'package:cupertino_ui/cupertino_ui.dart',
    isMaterial: false,
    package: 'cupertino_ui',
  ),
}

/// The library a shell is built with: `material_ui`, then `cupertino_ui`,
/// when a direct dependency and [available]; else the SDK's Material when
/// [available]; else none.
DesignLibrary? shellLibrary(
  Set<String> dependencies,
  bool Function(DesignLibrary) available,
) =>
    [DesignLibrary.materialUi, DesignLibrary.cupertinoUi]
        .where((l) => dependencies.contains(l.package) && available(l))
        .firstOrNull ??
    (available(DesignLibrary.material) ? DesignLibrary.material : null);

/// The design libraries available to the project, and the one its
/// default shell is built with.
class const DesignSupport({
  required final List<DesignLibrary> available,

  /// Library of the default shell; null for a plain `WidgetsApp`.
  required final DesignLibrary? shell,
}) {
  /// Detects libraries in the Flutter SDK and among the project's
  /// resolved packages. The default shell follows the project's direct
  /// dependencies: `material_ui`, then `cupertino_ui`, then the SDK's
  /// Material, then none.
  factory DesignSupport.detect(Project project, FlutterSdk sdk) {
    bool isAvailable(DesignLibrary library) => switch (library.package) {
      final package? => project.packageRoot(package) != null,
      null => File(
        p.join(
          sdk.root,
          'packages',
          'flutter',
          'lib',
          library.uri.split('/').last,
        ),
      ).existsSync(),
    };
    final available = DesignLibrary.values.where(isAvailable).toList();
    return DesignSupport(
      available: available,
      shell: shellLibrary(project.dependencies, available.contains),
    );
  }
}

/// Source of `shutter_design.dart`: `defaultShell` and `themeFallback`
/// for the harness, written against the available design libraries.
String designSource(DesignSupport design) {
  String prefix(DesignLibrary library) => '\$${library.name}';
  final buffer = StringBuffer(generatedHeader)
    ..writeln()
    ..writeln("import 'package:flutter/widgets.dart';");
  for (final library in design.available) {
    buffer.writeln("import '${library.uri}' as ${prefix(library)};");
  }
  buffer.writeln();

  final shell = switch (design.shell) {
    null =>
      'WidgetsApp(\n'
          '  color: const Color(0xFFFFFFFF),\n'
          '  debugShowCheckedModeBanner: false,\n'
          '  textStyle: const TextStyle(color: Color(0xFF000000)),\n'
          '  builder: (context, _) => child,\n'
          ')',
    final library when library.isMaterial =>
      '${prefix(library)}.MaterialApp(\n'
          '  debugShowCheckedModeBanner: false,\n'
          '  home: ${prefix(library)}.Material(child: child),\n'
          ')',
    final library =>
      '${prefix(library)}.CupertinoApp(\n'
          '  debugShowCheckedModeBanner: false,\n'
          '  home: child,\n'
          ')',
  };
  buffer
    ..writeln('/// The shell of shots without a project shell.')
    ..writeln('Widget defaultShell(Widget child) => $shell;')
    ..writeln()
    ..writeln(
      '/// Adds [families] to the text themes of every design library whose',
    )
    ..writeln(
      '/// theme is above [context]. Cupertino themes are wrapped innermost:',
    )
    ..writeln('/// a Material `Theme` inserts a Cupertino theme of its own.')
    ..writeln(
      'Widget themeFallback(BuildContext context, Widget child, '
      'List<String> families) {',
    )
    ..writeln('  var result = child;');
  final cupertino = design.available.where((l) => !l.isMaterial);
  if (cupertino.isNotEmpty) {
    buffer
      ..writeln('  TextStyle f(TextStyle style) =>')
      ..writeln('      style.copyWith(fontFamilyFallback: families);');
  }
  for (final library in [
    ...cupertino,
    ...design.available.where((l) => l.isMaterial),
  ]) {
    final d = prefix(library);
    if (library.isMaterial) {
      buffer.write('''
  if (context.findAncestorWidgetOfExactType<$d.Theme>() != null) {
    final theme = $d.Theme.of(context);
    result = $d.Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamilyFallback: families),
        primaryTextTheme: theme.primaryTextTheme.apply(
          fontFamilyFallback: families,
        ),
      ),
      child: result,
    );
  }
''');
    } else {
      buffer.write('''
  if (context.findAncestorWidgetOfExactType<$d.CupertinoTheme>() != null) {
    final theme = $d.CupertinoTheme.of(context);
    final text = theme.textTheme;
    result = $d.CupertinoTheme(
      data: theme.copyWith(
        textTheme: $d.CupertinoTextThemeData(
          primaryColor: theme.primaryColor,
          textStyle: f(text.textStyle),
          actionTextStyle: f(text.actionTextStyle),
          actionSmallTextStyle: f(text.actionSmallTextStyle),
          tabLabelTextStyle: f(text.tabLabelTextStyle),
          navTitleTextStyle: f(text.navTitleTextStyle),
          navLargeTitleTextStyle: f(text.navLargeTitleTextStyle),
          navActionTextStyle: f(text.navActionTextStyle),
          pickerTextStyle: f(text.pickerTextStyle),
          dateTimePickerTextStyle: f(text.dateTimePickerTextStyle),
        ),
      ),
      child: result,
    );
  }
''');
    }
  }
  buffer
    ..writeln('  return result;')
    ..writeln('}');
  return buffer.toString();
}
