import 'package:path/path.dart' as p;
import 'package:shutter/shutter.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  test('checks the project and the shell given, relative to the project '
      'directory', () {
    final root = createProject(files: {'.dart_tool/shutter/shell.dart': ''});
    final checks = doctor(root, shell: '.dart_tool/shutter/shell.dart');
    expect(
      checks,
      containsAll([
        DoctorCheck(CheckLevel.ok, 'project app at $root'),
        const DoctorCheck(CheckLevel.ok, 'shell .dart_tool/shutter/shell.dart'),
      ]),
    );
    expect(
      doctor(p.join(root, 'lib'), shell: 'nope.dart'),
      contains(
        const DoctorCheck(
          CheckLevel.fail,
          'shell lib/nope.dart does not exist',
          hint: 'run `shutter init --shell nope.dart` to write one',
        ),
      ),
    );
  });

  test('a directory outside any project fails the project check', () {
    expect(doctor(tempDir()).last.level, CheckLevel.fail);
  });
}
