@Tags(['e2e'])
library;

import 'package:shutter/src/run/manifest.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import 'e2e_helpers.dart';

void main() {
  test('--enter types into a field, in order with the taps', () async {
    final root = await exampleCopy();
    Future<(String, Map<String, Shot>)> shoot(List<String> args) =>
        shootIn(root, args);
    writeFiles(root, {
      'lib/preview/form_preview.dart': '''
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

@Preview(name: 'Form', size: Size(240, 160))
Widget form() => const Material(child: _Greeting());

class _Greeting extends StatefulWidget {
  const _Greeting();

  @override
  State<_Greeting> createState() => _GreetingState();
}

class _GreetingState extends State<_Greeting> {
  final controller = TextEditingController();
  String? shown;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      TextField(key: const ValueKey('name'), controller: controller),
      TextButton(
        onPressed: () => setState(
          () => shown = controller.text.isEmpty
              ? 'Name is empty'
              : 'Hello, \${controller.text}',
        ),
        child: const Text('Submit'),
      ),
      if (shown case final shown?) Text(shown),
    ],
  );
}
''',
    });
    const form = 'lib/preview/form_preview.dart';
    final (blank, _) = await shoot([form]);
    final (typed, typedShots) = await shoot([form, '--enter', 'key:name=Koji']);
    expect(typedShots['Form']!.status, ShotStatus.ok);
    expect((await shutter(root, ['diff', blank, typed])).exitCode, 1);
    final (enterFirst, _) = await shoot([
      form,
      '--enter',
      'key:name=Koji',
      '--tap',
      'text:Submit',
      '--settle',
      '700',
    ]);
    final (tapFirst, _) = await shoot([
      form,
      '--tap',
      'text:Submit',
      '--enter',
      'key:name=Koji',
      '--settle',
      '700',
    ]);
    expect((await shutter(root, ['diff', enterFirst, tapFirst])).exitCode, 1);
    final (_, noField) = await shoot([form, '--enter', 'text:Submit=x']);
    expect(
      noField['Form']!.error,
      'enter text:Submit=x: the widget holds no text field',
    );

    // Fields without keys are named by their labels: the example's
    // LoginForm, as the app has it.
    const login = [
      '--widget',
      'const LoginForm()',
      '--import',
      'lib/ui/login_form.dart',
      '--size',
      '390x400',
    ];
    final (empty, _) = await shoot(login);
    final (filled, filledShots) = await shoot([
      ...login,
      '--enter',
      'label:Email=example@example.com',
      '--enter',
      'label:Password=secret',
    ]);
    final signIn = filledShots.values.single;
    expect(signIn.status, ShotStatus.ok, reason: signIn.error);
    expect((await shutter(root, ['diff', empty, filled])).exitCode, 1);
  });
}
