import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'ui/settings_page.dart';

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'shutter example',
      theme: appTheme,
      darkTheme: appDarkTheme,
      home: const SettingsPage(),
    );
  }
}
