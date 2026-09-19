import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../ui/button.dart';
import '../ui/login_form.dart';

// Only the height is fixed: the button keeps its own width, so padding
// changes show up. A fixed width would stretch the button to that width.

@Preview(name: 'PrimaryButton / short', size: Size.fromHeight(56))
Widget buttonShort() => const PrimaryButton(label: 'OK');

@Preview(name: 'PrimaryButton / long', size: Size.fromHeight(56))
Widget buttonLong() => const PrimaryButton(label: 'Continue to checkout');

@Preview(name: 'PrimaryButton / Japanese', size: Size.fromHeight(56))
Widget buttonJapanese() => const PrimaryButton(label: '長いラベルのボタン 🎉');

@Preview(name: 'LoginForm', size: Size(390, 844))
Widget loginForm() => const LoginForm();
