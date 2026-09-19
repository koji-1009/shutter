import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../ui/greeting_card.dart';

/// Fonts fetched by google_fonts at runtime: shutter downloads them into
/// `.shutter/fonts/` and serves them as bundled assets.
@Preview(name: 'GreetingCard / google_fonts', size: Size(360, 140))
Widget greetingCard() =>
    const GreetingCard(title: 'Welcome', body: 'ようこそ、shutter へ');
