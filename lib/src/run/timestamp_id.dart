import 'dart:io';

import 'package:path/path.dart' as p;

/// Creates a new directory under [parent] named after [now] in UTC
/// (`20260918T101530Z`), suffixed `-2`, `-3`, ... when that name is
/// taken. Returns its path; its name is the run or diff id.
///
/// A name is claimed by creating the hidden file `<parent>/.<name>`
/// exclusively, so two processes starting in the same second get
/// different directories.
String createTimestampDir(String parent, DateTime now) {
  final u = now.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  final base =
      '${u.year.toString().padLeft(4, '0')}${two(u.month)}${two(u.day)}'
      'T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
  for (var n = 1; ; n++) {
    final name = n == 1 ? base : '$base-$n';
    final path = p.join(parent, name);
    if (Directory(path).existsSync()) continue;
    try {
      File(p.join(parent, '.$name'))
          .createSync(recursive: true, exclusive: true);
    } on FileSystemException {
      continue;
    }
    Directory(path).createSync(recursive: true);
    return path;
  }
}
