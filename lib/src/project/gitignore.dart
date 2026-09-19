import 'dart:io';

import 'package:path/path.dart' as p;

const _entry = '.shutter/';

/// Makes sure `<root>/.gitignore` ignores `.shutter/`, creating the file
/// when it is missing.
void ensureGitignored(String root) {
  final file = File(p.join(root, '.gitignore'));
  final content = file.existsSync() ? file.readAsStringSync() : '';
  if (isGitignored(content)) return;
  final separator = content.isEmpty || content.endsWith('\n') ? '' : '\n';
  file.writeAsStringSync('$content$separator$_entry\n');
}

/// True when a `.gitignore` body already ignores `.shutter/`.
bool isGitignored(String content) => content
    .split('\n')
    .map((line) => line.trim())
    .any(
      (line) => const {
        '.shutter',
        '.shutter/',
        '/.shutter',
        '/.shutter/',
      }.contains(line),
    );
