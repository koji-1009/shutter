import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';

import '../project/project.dart';
import '../shutter_exception.dart';
import 'candidate.dart';

/// The library declaring `Preview` and `MultiPreview`.
const _previewLibrary =
    'package:flutter/src/widget_previews/widget_previews.dart';

/// Finds the previews of given files under `lib/` with the analyzer's
/// resolution. See `doc/manual.md` ("How previews are found") for the
/// rules.
class Scanner(
  final Project project, {

  /// Dart SDK the project is analyzed against (the Flutter SDK's).
  required final String sdkPath,
}) {
  /// Resolves [paths] (absolute library files under `lib/`) and returns
  /// the libraries holding previews.
  Future<List<SourceLibrary>> scan(List<String> paths) async {
    if (paths.isEmpty) return const [];
    final collection = AnalysisContextCollection(
      includedPaths: [project.libDir],
      sdkPath: sdkPath,
    );
    try {
      final libraries = <SourceLibrary>[];
      for (final path in paths.toSet()) {
        final session = collection.contextFor(path).currentSession;
        final unit = await session.getResolvedUnit(path) as ResolvedUnitResult;
        if (!unit.isLibrary) {
          throw ShutterException.usage(
            '${project.relative(path)} is a part; name its library file.',
          );
        }
        final file = project.relative(path);
        final library = _Library(unit, file);
        final candidates = library.candidates();
        if (candidates.isEmpty) continue;
        libraries.add(
          SourceLibrary(
            file: file,
            imports: library.imports,
            candidates: candidates,
          ),
        );
      }
      return libraries;
    } finally {
      await collection.dispose();
    }
  }
}

/// One library being scanned: its candidates and the prefixed imports
/// their generated code needs.
class _Library(
  /// The library file, resolved.
  final ResolvedUnitResult unit,

  /// Project-relative path of the library file.
  final String file,
) {
  final LibraryElement element = unit.libraryElement;

  final _prefixes = <String, String>{};

  /// `import '<uri>' as $iN;`, in order of first use.
  List<String> get imports => [
    for (final MapEntry(key: uri, value: prefix) in _prefixes.entries)
      '$uri as $prefix;',
  ];

  List<Candidate> candidates() {
    final candidates = <Candidate>[];

    void add(NodeList<Annotation> metadata, String symbol) {
      for (final (index, annotation) in metadata.indexed) {
        final type = _annotationClass(annotation);
        if (type == null
            ? !annotation.name.toSource().contains('Preview')
            : !_isPreview(type)) {
          continue;
        }
        final location = unit.lineInfo.getLocation(annotation.offset);
        final rewriter = _Rewriter(this)..rewrite(annotation);
        final text = rewriter.text(unit.content, annotation);
        final diagnostic = unit.diagnostics
            .where(
              (d) =>
                  d.severity == Severity.error &&
                  d.offset >= annotation.offset &&
                  d.offset < annotation.end,
            )
            .firstOrNull;
        candidates.add(
          Candidate(
            file: file,
            line: location.lineNumber,
            column: location.columnNumber,
            symbol: symbol,
            annotationIndex: index,
            annotation: annotation.arguments == null ? text : 'const $text',
            target: '${_prefixFor(_selfImport)}.$symbol',
            error:
                (type == null
                    ? 'annotation does not resolve: '
                          '${diagnostic?.message ?? annotation.name.toSource()}'
                    : null) ??
                diagnostic?.message ??
                rewriter.error,
          ),
        );
      }
    }

    for (final declaration in unit.unit.declarations) {
      switch (declaration) {
        case FunctionDeclaration(:final name, propertyKeyword: null)
            when !Identifier.isPrivateName(name.lexeme):
          add(declaration.metadata, name.lexeme);
        case ClassDeclaration(:final namePart, :final declaredFragment?)
            when !Identifier.isPrivateName(namePart.typeName.lexeme):
          final className = namePart.typeName.lexeme;
          final constructable = declaredFragment.element.isConstructable;
          for (final member in declaration.body.members) {
            final name = switch (member) {
              MethodDeclaration(isStatic: true, :final name)
                  when !member.isGetter &&
                      !member.isSetter &&
                      !member.isOperator =>
                name.lexeme,
              ConstructorDeclaration(:final factoryKeyword, :final name)
                  when factoryKeyword != null || constructable =>
                name?.lexeme ?? 'new',
              _ => null,
            };
            if (name == null || Identifier.isPrivateName(name)) continue;
            add(member.metadata, '$className.$name');
          }
        default:
      }
    }
    return candidates;
  }

  String get _selfImport => "import '${element.uri}'";

  /// The prefix of an import reaching [directive] (`import '<uri>'`).
  String _prefixFor(String directive) =>
      _prefixes.putIfAbsent(directive, () => '\$i${_prefixes.length}');

  /// `$iN.name` reaching the top-level [element] from generated code:
  /// through the library itself when it declares it, else through the
  /// library's import that provides it (conditional configurations kept),
  /// else through the declaring library.
  String reference(Element element, String name) {
    final String directive;
    if (element.library == this.element) {
      directive = _selfImport;
    } else {
      directive =
          unit.unit.directives
              .whereType<ImportDirective>()
              .where(
                (d) =>
                    d
                        .libraryImport
                        ?.namespace
                        .definedNames2[name]
                        ?.baseElement ==
                    element.baseElement,
              )
              .map(_directiveText)
              .firstOrNull ??
          "import '${element.library!.uri}'";
    }
    return '${_prefixFor(directive)}.$name';
  }

  /// `import '<uri>' if (...) '<uri>'`: [directive] without prefix and
  /// combinators, relative URIs made `package:` URIs.
  String _directiveText(ImportDirective directive) {
    final content = unit.content;
    final base = element.uri;
    final literals = [
      directive.uri,
      for (final configuration in directive.configurations) configuration.uri,
    ];
    final start = directive.uri.offset;
    final end = directive.configurations.lastOrNull?.end ?? directive.uri.end;
    var text = content.substring(start, end);
    for (final literal in literals.reversed) {
      final value = literal.stringValue!;
      if (Uri.parse(value).hasScheme) continue;
      final offset = literal.offset - start;
      text = text.replaceRange(
        offset,
        offset + literal.length,
        "'${base.resolve(value)}'",
      );
    }
    return 'import $text';
  }
}

/// The class of the object [annotation] evaluates to, or null when it
/// does not resolve.
InterfaceElement? _annotationClass(Annotation annotation) =>
    switch (annotation.element) {
      ConstructorElement(:final enclosingElement) => enclosingElement,
      ExecutableElement(returnType: InterfaceType(:final element)) => element,
      _ => null,
    };

bool _isPreview(InterfaceElement type) =>
    [type.thisType, ...type.allSupertypes].any(
      (t) =>
          const {'Preview', 'MultiPreview'}.contains(t.element.name) &&
          t.element.library.uri.toString() == _previewLibrary,
    );

/// Rewrites an annotation so every name goes through an import prefix,
/// and notes a private name generated code cannot reach.
class _Rewriter(final _Library library) extends RecursiveAstVisitor<void> {
  final _replacements = <(int, int, String)>[];
  String? error;

  void rewrite(Annotation annotation) => annotation.accept(this);

  /// [annotation]'s source from its name on, rewritten.
  String text(String content, Annotation annotation) {
    final start = annotation.name.offset;
    var text = content.substring(start, annotation.end);
    for (final (from, to, replacement) in _replacements.reversed) {
      text = text.replaceRange(from - start, to - start, replacement);
    }
    return text;
  }

  void _replace(int from, int to, Element? element) {
    if (element == null) return;
    final String text;
    switch (element.enclosingElement) {
      case LibraryElement():
        text = library.reference(element, element.name!);
      // Static members are read through getters and methods; constructors
      // reach here only from dot shorthands.
      case InstanceElement(:final name?)
          when element is ConstructorElement ||
              element is ExecutableElement && element.isStatic:
        text =
            '${library.reference(element.enclosingElement!, name)}.'
            '${element.name}';
      default:
        return;
    }
    for (final name in [
      element.name,
      if (element.enclosingElement case InstanceElement(:final name)) name,
    ].nonNulls) {
      _notePrivate(name);
    }
    _replacements.add((from, to, text));
  }

  void _notePrivate(String name) {
    if (!Identifier.isPrivateName(name)) return;
    error ??=
        'annotation references private `$name`, which generated code '
        'cannot reach';
  }

  @override
  void visitNamedType(NamedType node) {
    _replace(
      node.importPrefix?.offset ?? node.name.offset,
      node.name.end,
      node.element,
    );
    node.typeArguments?.accept(this);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (node.prefix.element is PrefixElement) {
      _replace(node.offset, node.end, node.identifier.element);
      return;
    }
    super.visitPrefixedIdentifier(node);
  }

  // A dot shorthand (`.dark`, `.named()`) is replaced from its period on,
  // spelling out the class it resolves against.
  @override
  void visitDotShorthandPropertyAccess(DotShorthandPropertyAccess node) =>
      _replace(node.period.offset, node.end, node.propertyName.element);

  @override
  void visitDotShorthandInvocation(DotShorthandInvocation node) {
    _replace(node.period.offset, node.memberName.end, node.memberName.element);
    node.typeArguments?.accept(this);
    node.argumentList.accept(this);
  }

  @override
  void visitDotShorthandConstructorInvocation(
    DotShorthandConstructorInvocation node,
  ) {
    _replace(
      node.period.offset,
      node.constructorName.end,
      node.constructorName.element,
    );
    node.typeArguments?.accept(this);
    node.argumentList.accept(this);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final parent = node.parent;
    if (parent is Label) return;
    final selector = switch (parent) {
      PrefixedIdentifier(:final identifier) => identifier == node,
      PropertyAccess(:final propertyName) => propertyName == node,
      ConstructorName(:final name) => name == node,
      Annotation(:final constructorName) => constructorName == node,
      _ => false,
    };
    // A selector (`Class._member`, `Class._named()`) keeps its text; a
    // private one is as unreachable as a private top-level name.
    if (selector) {
      _notePrivate(node.name);
    } else {
      _replace(node.offset, node.end, node.element);
    }
  }
}
