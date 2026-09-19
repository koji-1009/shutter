import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

/// An 8×8 orange PNG, decoded before capture.
final _swatch = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEklEQVR4nGN4FsiAFWEXHbQSAJsKTcHRh2yzAAAAAElFTkSuQmCC',
);

@Preview(name: 'Swatch / memory image', size: Size(64, 64))
Widget swatch() =>
    Image.memory(_swatch, width: 64, height: 64, fit: BoxFit.fill);

/// Fails on purpose: HTTP is blocked while rendering, so a
/// `NetworkImage` becomes an `error` shot with the image's location.
@Preview(name: 'Avatar / network image', size: Size(64, 64))
Widget avatar() => Image.network('https://example.com/avatar.png');

PreviewLocalizationsData english() => const PreviewLocalizationsData(
  locale: Locale('en', 'US'),
  localizationsDelegates: [
    DefaultMaterialLocalizations.delegate,
    DefaultWidgetsLocalizations.delegate,
  ],
);

@Preview(
  name: 'OK label / localizations',
  size: Size(120, 48),
  localizations: english,
)
Widget okLabel() => Builder(
  builder: (context) =>
      Center(child: Text(MaterialLocalizations.of(context).okButtonLabel)),
);
