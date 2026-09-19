import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shutter/src/project/gitignore.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  String read(String root) =>
      File(p.join(root, '.gitignore')).readAsStringSync();

  test('creates .gitignore when missing', () {
    final root = tempDir();
    ensureGitignored(root);
    expect(read(root), '.shutter/\n');
  });

  test('appends once, adding a newline when the file lacks one', () {
    final root = tempDir();
    writeFiles(root, {'.gitignore': 'build/'});
    ensureGitignored(root);
    expect(read(root), 'build/\n.shutter/\n');
    ensureGitignored(root);
    expect(read(root), 'build/\n.shutter/\n');
  });

  test('appends to an empty file and to one ending in a newline', () {
    final empty = tempDir();
    writeFiles(empty, {'.gitignore': ''});
    ensureGitignored(empty);
    expect(read(empty), '.shutter/\n');
    final trailing = tempDir();
    writeFiles(trailing, {'.gitignore': 'a\n'});
    ensureGitignored(trailing);
    expect(read(trailing), 'a\n.shutter/\n');
  });

  test('recognises the usual spellings', () {
    for (final line in ['.shutter', '.shutter/', '/.shutter', ' /.shutter/ ']) {
      expect(isGitignored('x\n$line\n'), isTrue, reason: line);
    }
    expect(isGitignored('.shutter_other\n'), isFalse);
  });
}
