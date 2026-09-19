import 'package:path/path.dart' as p;
import 'package:shutter/src/project/project.dart';
import 'package:shutter/src/scan/candidate.dart';
import 'package:shutter/src/scan/scanner.dart';
import 'package:shutter/src/shutter_exception.dart';
import 'package:test/test.dart';

import '../helpers.dart';

const previews =
    "import 'package:flutter/widget_previews.dart';\n"
    "import 'package:flutter/widgets.dart';\n";

/// Scans [only], or every `lib/` file of [files].
Future<List<SourceLibrary>> scan(
  Map<String, String> files, {
  List<String>? only,
}) {
  final root = createProject(files: files, resolvable: true);
  return Scanner(Project.load(root), sdkPath: dartSdk).scan([
    for (final file in only ?? files.keys)
      if (file.startsWith('lib/')) p.join(root, file),
  ]);
}

void main() {
  test('resolves a top-level preview: prefixed imports, annotation, target, '
      'and position', () async {
    final library = (await scan({
      'lib/preview/a.dart':
          '''
${previews}import '../ui/button.dart';

@Preview(name: 'A', size: Size(10, 20))
Widget a() => const Button();
''',
      'lib/ui/button.dart': '''
import 'package:flutter/widgets.dart';

class Button extends Widget {
  const Button();
}
''',
    })).single;
    expect(library.file, 'lib/preview/a.dart');
    expect(library.imports, [
      r"import 'package:flutter/widget_previews.dart' as $i0;",
      r"import 'package:flutter/widgets.dart' as $i1;",
      r"import 'package:app/preview/a.dart' as $i2;",
    ]);
    final c = library.candidates.single;
    expect(c.symbol, 'a');
    expect((c.line, c.column, c.annotationIndex), (5, 1, 0));
    expect(
      c.annotation,
      r"const $i0.Preview(name: 'A', size: $i1.Size(10, 20))",
    );
    expect(c.target, r'$i2.a');
    expect(c.error, isNull);
    expect(c.staticId, shotStaticId('lib/preview/a.dart', 'a', 0));
  });

  test('only Flutter\'s Preview and MultiPreview make previews; a '
      'MultiPreview subclass keeps its type arguments', () async {
    final libraries = await scan({
      'lib/own.dart': '''
import 'package:flutter/widgets.dart';

/// Named like Flutter's, declared here.
class Preview {
  const Preview();
}

@Preview()
Widget own() => const Text('');
''',
      'lib/multi.dart':
          '''
$previews
final class Pair<T> extends MultiPreview {
  const Pair();
  @override
  List<Preview> get previews => const [Preview(name: 'x')];
}
@Pair<Text>()
Widget pair() => const Text('');
''',
    });
    final c = libraries.single.candidates.single;
    expect(c.file, 'lib/multi.dart');
    expect(c.annotation, r'const $i0.Pair<$i1.Text>()');
    expect(c.error, isNull);
  });

  test('an error in the body, not the annotation, leaves the candidate '
      'to the compiler', () async {
    final c = (await scan({
      'lib/a.dart': '$previews@Preview()\nWidget a() => const Missing();',
    })).single.candidates.single;
    expect(c.error, isNull);
  });

  test('skips files without annotations, other annotations, private and '
      'accessor declarations', () async {
    final libraries = await scan({
      'lib/plain.dart': 'int x() => 0;',
      'lib/a.dart':
          '''
$previews
@Deprecated('x')
Widget deprecated() => const Text('');
@Preview()
Widget _private() => const Text('');
@Preview()
Widget get getter => const Text('');
@Preview()
set setter(Widget w) {}
Widget bare() => const Text('');
class _Hidden {
  @Preview()
  static Widget s() => const Text('');
}
''',
    });
    expect(libraries, isEmpty);
  });

  test('counts every annotation; an identifier annotation is a '
      'reference', () async {
    final c = (await scan({
      'lib/a.dart':
          '''
$previews
const p = Preview();
@Deprecated('x')
@p
Widget a() => const Text('');
''',
    })).single.candidates.single;
    expect(c.annotation, r'$i0.p');
    expect(c.annotationIndex, 1);
  });

  test('static methods and constructors of classes that can be '
      'instantiated', () async {
    final c = (await scan({
      'lib/a.dart':
          '''
$previews
class Card extends Widget {
  @Preview()
  const Card();
  @Preview()
  const Card.named();
  @Preview()
  factory Card.make() => const Card();
  @Preview()
  static Widget s() => const Card();
  @Preview()
  Widget instance() => const Card();
  @Preview()
  static Widget get g => const Card();
  @Preview()
  const Card._private();
  @Preview()
  static Widget _p() => const Card();
  @Preview()
  static Widget operator() => const Card();
}
abstract class Base extends Widget {
  @Preview()
  const Base();
  @Preview()
  factory Base.make() => const Card();
}
sealed class Sealed extends Widget {
  @Preview()
  const Sealed();
  @Preview()
  factory Sealed.make() => const Card();
}
''',
    })).single.candidates;
    expect(c.map((c) => c.symbol), [
      'Card.new',
      'Card.named',
      'Card.make',
      'Card.s',
      'Card.operator',
      'Base.make',
      'Sealed.make',
    ]);
    expect(c.first.target, r'$i1.Card.new');
  });

  test(
    'qualifies static members of the class, bare or as the annotation',
    () async {
      final c = (await scan({
        'lib/a.dart':
            '''
$previews
class Card {
  static Widget wrap(Widget w) => w;
  static const kSize = Size(1, 2);
  static const kPreview = Preview(name: 'k');
  @Preview(wrapper: wrap, size: kSize)
  static Widget s() => const Text('');
  @kPreview
  static Widget t() => const Text('');
  @Card.kPreview
  static Widget u() => const Text('');
}
''',
      })).single.candidates;
      expect(c.map((c) => c.annotation), [
        r'const $i0.Preview(wrapper: $i1.Card.wrap, size: $i1.Card.kSize)',
        r'$i1.Card.kPreview',
        r'$i1.Card.kPreview',
      ]);
    },
  );

  test('spells out the class of dot shorthands', () async {
    final c = (await scan({
      'lib/a.dart':
          '''
$previews
class Spec {
  const Spec();
  const Spec.named();
  const Spec.wrap(Spec spec);
  static const big = Spec();
  static Spec of(int i) => const Spec();
}
class P extends Preview {
  const P({Spec? spec, List<Spec>? specs, Size? size}) : super();
}
@Preview(brightness: .dark)
Widget a() => const Text('');
@P(spec: .big, specs: [.big], size: Size(.infinity, 1))
Widget b() => const Text('');
@P(spec: .named())
Widget c() => const Text('');
@P(spec: .new())
Widget d() => const Text('');
@P(spec: .wrap(.big))
Widget e() => const Text('');
@P(spec: .of(1))
Widget f() => const Text('');
''',
    })).single.candidates;
    expect(c.map((c) => c.annotation), [
      r'const $i0.Preview(brightness: $i1.Brightness.dark)',
      (r'const $i2.P(spec: $i2.Spec.big, specs: [$i2.Spec.big], '
          r'size: $i1.Size($i3.double.infinity, 1))'),
      r'const $i2.P(spec: $i2.Spec.named())',
      r'const $i2.P(spec: $i2.Spec.new())',
      r'const $i2.P(spec: $i2.Spec.wrap($i2.Spec.big))',
      r'const $i2.P(spec: $i2.Spec.of(1))',
    ]);
    expect(c.take(5).map((c) => c.error), everyElement(isNull));
    expect(c.last.error, isNotNull);
  });

  test("the library's own declarations shadow imported ones", () async {
    final library = (await scan({
      'lib/a.dart':
          '''
$previews
import 'package:flutter/material.dart';

class Badge extends Widget {
  @Preview()
  const Badge();
}
''',
    })).single;
    expect(library.candidates.single.target, r'$i1.Badge.new');
    expect(library.imports.last, r"import 'package:app/a.dart' as $i1;");
  });

  test('keeps conditional configurations, drops prefixes and combinators, '
      'and reaches dart:core directly', () async {
    final library = (await scan({
      'lib/preview/a.dart': '''
import 'package:flutter/widget_previews.dart' as wp show Preview;
import 'package:flutter/widgets.dart' as w;
import 'names.dart' if (dart.library.io) 'io_names.dart';

@wp.Preview(name: kName, size: w.Size(double.infinity, 1))
w.Widget a() => const w.Text('');
''',
      'lib/preview/names.dart': "const kName = 'stub';",
      'lib/preview/io_names.dart': "const kName = 'io';",
    })).single;
    expect(library.imports, [
      r"import 'package:flutter/widget_previews.dart' as $i0;",
      ("import 'package:app/preview/names.dart' if (dart.library.io) "
          r"'package:app/preview/io_names.dart' as $i1;"),
      r"import 'package:flutter/widgets.dart' as $i2;",
      r"import 'dart:core' as $i3;",
      r"import 'package:app/preview/a.dart' as $i4;",
    ]);
    expect(
      library.candidates.single.annotation,
      r'const $i0.Preview(name: $i1.kName, size: $i2.Size($i3.double.infinity, 1))',
    );
  });

  test('references to private names are errors', () async {
    final c = (await scan({
      'lib/a.dart':
          '''
$previews
Widget _wrap(Widget w) => w;
class _Hidden {
  static const size = Size(1, 1);
}
class Shown {
  static Widget _wrap(Widget w) => w;
  static const _size = Size(1, 1);
}
class Named extends Preview {
  const Named._() : super();
  static const preview = Named._();
}
@Preview(wrapper: _wrap)
Widget a() => const Text('');
@Preview(size: _Hidden.size)
Widget b() => const Text('');
@Preview()
Widget c() => const Text('');
@Preview(wrapper: Shown._wrap)
Widget d() => const Text('');
@Preview(size: Shown._size)
Widget e() => const Text('');
@Named._()
Widget f() => const Text('');
class Local {
  const Local._hidden();
  static const _secret = Local._hidden();
}
class Q extends Preview {
  const Q({Local? local}) : super();
}
@Q(local: ._hidden())
Widget g() => const Text('');
@Q(local: ._secret)
Widget h() => const Text('');
''',
    })).single.candidates;
    expect(c[0].error, contains('private `_wrap`'));
    expect(c[1].error, contains('private `_Hidden`'));
    expect(c[2].error, isNull);
    expect(c[3].error, contains('private `_wrap`'));
    expect(c[4].error, contains('private `_size`'));
    expect(c[5].error, contains('private `_`'));
    expect(c[6].error, contains('private `_hidden`'));
    expect(c[7].error, contains('private `_secret`'));
  });

  test('annotations that do not resolve are errors', () async {
    final c = (await scan({
      'lib/a.dart':
          '''
$previews
@MissingPreview()
Widget a() => const Text('');
@Preview(name: missing)
Widget b() => const Text('');
@unknown
Widget c() => const Text('');
''',
    })).single.candidates;
    expect(c, hasLength(2));
    expect(c[0].error, startsWith('annotation does not resolve: '));
    expect(c[0].error, contains('MissingPreview'));
    expect(c[1].error, contains('missing'));
  });

  test('a part file is a usage error', () async {
    await expectLater(
      scan(
        {
          'lib/lib.dart': "${previews}part 'part.dart';",
          'lib/part.dart':
              "part of 'lib.dart';\n@Preview()\nWidget a() => const Text('');",
        },
        only: ['lib/part.dart'],
      ),
      throwsA(
        isA<ShutterException>()
            .having((e) => e.exitCode, 'exitCode', 64)
            .having((e) => e.message, 'message', contains('is a part')),
      ),
    );
  });

  test('scans only the named files; none, nothing', () async {
    final libraries = await scan(
      {
        'lib/a.dart': "$previews@Preview()\nWidget a() => const Text('');",
        'lib/b.dart': "$previews@Preview()\nWidget b() => const Text('');",
      },
      only: ['lib/b.dart', 'lib/b.dart'],
    );
    expect(libraries.single.file, 'lib/b.dart');
    expect(libraries.single.candidates.single.symbol, 'b');
    expect(
      await Scanner(Project.load(createProject()), sdkPath: dartSdk).scan([]),
      isEmpty,
    );
  });
}
