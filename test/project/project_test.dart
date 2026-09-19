import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shutter/src/project/project.dart';
import 'package:shutter/src/shutter_exception.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  test('find walks up to the nearest pubspec.yaml', () {
    final root = createProject(files: {'lib/src/x.dart': ''});
    final project = Project.find(p.join(root, 'lib', 'src'));
    expect(project.root, root);
    expect(project.name, 'app');
    expect(project.isApp, isTrue);
    expect(project.hasFlutterTest, isTrue);
  });

  test('find fails without a pubspec.yaml up to the file system root', () {
    expect(
      () => Project.find(tempDir()),
      throwsA(
        isA<ShutterException>().having(
          (e) => e.message,
          'message',
          startsWith('no pubspec.yaml found'),
        ),
      ),
    );
  });

  test('load rejects invalid YAML and a missing name', () {
    final bad = tempDir();
    writeFiles(bad, {'pubspec.yaml': 'name: [unclosed'});
    expect(
      () => Project.load(bad),
      throwsA(
        isA<ShutterException>().having(
          (e) => e.message,
          'message',
          contains('is not valid YAML'),
        ),
      ),
    );
    final nameless = tempDir();
    writeFiles(nameless, {'pubspec.yaml': 'version: 1.0.0'});
    expect(() => Project.load(nameless), throwsA(isA<ShutterException>()));
    final list = tempDir();
    writeFiles(list, {'pubspec.yaml': '- a'});
    expect(() => Project.load(list), throwsA(isA<ShutterException>()));
  });

  test('reads publish_to and flutter_test', () {
    final package = Project.load(
      createProject(name: 'pkg', app: false, flutterTest: false),
    );
    expect(package.isApp, isFalse);
    expect(package.hasFlutterTest, isFalse);
  });

  test('preview dir: lib/preview for apps, lib/src/preview for packages '
      'or when it exists', () {
    final app = Project.load(createProject());
    expect(app.previewDir, p.join(app.root, 'lib', 'preview'));
    expect(app.shellPath, isNull);
    writeFiles(app.root, {'lib/preview/shell.dart': ''});
    expect(app.shellPath, p.join(app.root, 'lib', 'preview', 'shell.dart'));

    final package = Project.load(createProject(app: false));
    expect(package.previewDir, p.join(package.root, 'lib', 'src', 'preview'));

    Directory(p.join(app.root, 'lib', 'src', 'preview'))
        .createSync(recursive: true);
    expect(app.previewDir, p.join(app.root, 'lib', 'src', 'preview'));
  });
}
