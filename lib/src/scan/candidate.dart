import 'dart:convert';

import 'package:crypto/crypto.dart';

/// A declaration carrying a `Preview` or `MultiPreview` annotation, as
/// resolved by the analyzer, with the Dart code generated code uses to
/// rebuild the annotation and to call the declaration.
class Candidate({
  /// Project-relative POSIX path of the file holding the declaration.
  required final String file,

  /// 1-based position of the annotation.
  required final int line,
  required final int column,

  /// `fn`, `Class.method`, `Class.new`, or `Class.named`.
  required final String symbol,

  /// Position of the annotation among every annotation on the
  /// declaration. Part of the static id.
  required final int annotationIndex,

  /// The annotation as a Dart expression in which every name is reached
  /// through an import prefix of [SourceLibrary.imports].
  required final String annotation,

  /// The declaration as a tear-off through an import prefix
  /// (`$i0.fn`, `$i0.Card.new`).
  required final String target,

  /// Set when the candidate cannot be shot (an annotation that does not
  /// resolve, a private reference); the candidate becomes an error shot
  /// without being compiled.
  final String? error,
}) {
  /// First 16 hex of `sha256("<file>|<symbol>|<annotationIndex>")`.
  String get staticId => shotStaticId(file, symbol, annotationIndex);
}

/// Static half of a shot id. The runtime half (the index of the
/// `Preview` produced by `transform()`) is appended after a `.`.
String shotStaticId(String file, String symbol, int annotationIndex) =>
    shortHash('$file|$symbol|$annotationIndex');

/// First 16 hex digits of `sha256(input)`.
String shortHash(String input) =>
    sha256.convert(utf8.encode(input)).toString().substring(0, 16);

/// One Dart library holding candidates, with the imports generated code
/// needs to reach every name its candidates use.
class SourceLibrary({
  /// Project-relative POSIX path of the library file.
  required final String file,

  /// Prefixed `import` directives (`import '...' as $i0;`), conditional
  /// configurations kept from the library's own imports.
  required final List<String> imports,
  required final List<Candidate> candidates,
});
