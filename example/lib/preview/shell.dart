import 'package:flutter/material.dart';

import '../app_theme.dart';

/// App-level ambient for every preview without its own `wrapper`.
Widget shell(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: appTheme,
  darkTheme: appDarkTheme,
  home: Material(child: child),
);
