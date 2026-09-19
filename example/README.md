# shutter example

A small Flutter app with previews under `lib/preview/`, used by shutter's end-to-end tests and as a playground.

* `button_preview.dart` — `PrimaryButton` with a short, a long, and a Japanese label, and the `LoginForm` that contains it.
* `settings_page_preview.dart` — a phone-sized screen.
* `inbox_preview.dart` — a `MultiPreview` rendering each state (empty, loading, error, loaded) in light and dark.
* `misc_preview.dart` — static-method previews with a `wrapper`, a `theme`, a `WidgetBuilder` with `textScaleFactor`, and one preview that overflows on purpose.
* `media_preview.dart` — a memory image, a network image (an `error` shot: HTTP is blocked while rendering), and `localizations`.
* `google_fonts_preview.dart` — text in google_fonts families, fetched once into `.shutter/fonts/`.
* `shell.dart` — the app theme around every preview without its own `wrapper`.

```bash
cd example
flutter pub get
dart run ../bin/shutter.dart shot lib/preview/button_preview.dart   # prints run: <before-run>
# edit lib/ui/button.dart
dart run ../bin/shutter.dart shot lib/preview/button_preview.dart   # prints run: <after-run>
dart run ../bin/shutter.dart diff <before-run> <after-run>
```
