# shutter

[![pub package](https://img.shields.io/pub/v/shutter.svg)](https://pub.dev/packages/shutter)
[![GitHub license](https://img.shields.io/github/license/koji-1009/shutter)](https://github.com/koji-1009/shutter/blob/main/LICENSE)
[![CI](https://github.com/koji-1009/shutter/actions/workflows/analyze.yml/badge.svg)](https://github.com/koji-1009/shutter/actions/workflows/analyze.yml)
[![codecov](https://codecov.io/gh/koji-1009/shutter/branch/main/graph/badge.svg)](https://codecov.io/gh/koji-1009/shutter)

Shutter renders Flutter widgets to PNG and compares two runs pixel by pixel, so an AI agent can attach a visual change to its PR as before and after images.
Any widget can be shot, from a single button to a whole `Scaffold` screen: import it into a small preview file, and shutter renders it through Flutter's widget preview.

> **AI agents — start here:** run `shutter agent` before driving the tool. It is the step-by-step playbook: putting a widget in the preview dir, shooting before and after, and reading the diff. `shutter manual` is the reference. Both ship in the binary, so `dart install shutter` is enough.

## What it does

A visual change is closed by an image, not by "it compiles" or "the tests pass". Shutter gives that image without launching the app and without writing a test:

* `shutter shot <preview-file>...` renders the widgets of the named preview files to PNG. A preview file imports any widget of the app and returns it from a function annotated with Flutter's `@Preview`; the widget itself needs no annotation.
* `shutter diff <run-a> <run-b>` classifies each shot of two runs as `changed`, `added`, `removed`, or `unchanged`, and points at its before and after images (`--images` adds an image marking the differing pixels).
* `shutter shot --widget '<expression>'` renders one widget without a file, for a quick look.

Each command does one thing and prints paths, so it composes with `grep`, `git`, `gh`, and whatever opens images.
Shutter makes no judgement: it does not decide what to shoot, whether a change is good, or where to post.
It keeps no golden images and knows nothing about git; every comparison is between two runs you made.

## Install

```bash
dart install shutter
```

The target project needs Flutter 3.47+ (Dart 3.13+) and `flutter_test` in `dev_dependencies`. It gains no dependency on shutter.
Shutter finds the Flutter SDK through `FLUTTER_ROOT`, or through `flutter` on `PATH` (a version manager's shim included).

### Agent skill

The package ships an [agent skill](https://dart.dev/tools/pub/package-skills), `shutter-visual-check`, telling an AI agent to reach for shutter when a change affects how a widget looks. It points at `shutter agent`, so the playbook always matches the installed binary.

```bash
dart run skills@ add koji-1009/shutter    # from the repository; the project gains no dependency
```

A project that lists shutter in `dev_dependencies` gets it with `dart run skills@ get` instead.

## Quick start

Put the widget you are changing in the preview dir (`lib/preview/`, or `lib/src/preview/` in a package):

```dart
// lib/preview/settings_page_preview.dart
import 'package:flutter/widget_previews.dart';
import 'package:flutter/widgets.dart';

import '../settings_page.dart';

@Preview(name: 'SettingsPage', size: Size(390, 844))
Widget settingsPage() => const SettingsPage();
```

Shoot before and after the edit, then compare:

```bash
shutter shot lib/preview/settings_page_preview.dart   # prints the run directory as run:
# ... edit ...
shutter shot lib/preview/settings_page_preview.dart
shutter diff <before-run> <after-run>
```

The output is YAML for agents; `diff` lists each shot with the absolute paths of its before and after images.
The preview file stays in the project: the same function shows up in Flutter's widget previewer, and the next change is shot against it.

Every shot is wrapped in a shell: the project's `shell.dart` with the app's own app widget, theme, router, and providers (`shutter init` writes one), or a default shell.
Shutter itself depends on no design library, so Material, Cupertino, and custom widget sets all work.

A widget can also be shot without a file:

```bash
shutter shot --widget 'PrimaryButton(label: "OK")' --import lib/ui/button.dart --size 200x56
```

`--import` names a file the widget expression needs imported (repeatable; `package:flutter/widgets.dart` is always imported).
The same `--widget` and `--import` give the same shot id, so two such runs line up in `diff`.

## Subcommands

| Command        | Purpose                                                                                                         |
| -------------- | --------------------------------------------------------------------------------------------------------------- |
| `agent`        | The step-by-step playbook for AI agents.                                                                        |
| `manual`       | The reference: preview files, drawing model, engine, runs, ids, diff, output, exit codes.                       |
| `doctor`       | Check the Flutter SDK version, its font cache, and the project's shell.                                         |
| `init`         | Write `<preview dir>/shell.dart`.                                                                               |
| `shot`         | Render the named preview files, or one `--widget`, into a new run (`--widget`/`--import`/`--size`, `--settle`). |
| `diff <a> <b>` | Compare two runs (`--images`).                                                                                  |

## Exit codes

| Command  | 0               | 1              | 2                |
| -------- | --------------- | -------------- | ---------------- |
| `shot`   | every shot ok   | —              | any shot `error` |
| `diff`   | no difference   | differences    | —                |
| `doctor` | no failed check | a failed check | —                |

`diff` exiting 1 means "changed", not "failed". Other failures follow sysexits: 64 usage, 66 missing run or file, 69 no Flutter SDK, 70 internal error, 78 project not usable.

## Limits

* One frame, no interaction: taps, hovers, scrolling, and mid-animation states are not shot. State comes from the widget's construction expression.
* HTTP is blocked while rendering, so network images fail to load.
* Text renders with the project's fonts plus Roboto; CJK and emoji fall back to the host's system fonts, and Cupertino text uses SF Pro on macOS (Roboto elsewhere), as a device would. Compare runs made on the same machine.

## Experimental

Behaviour whose specification is not settled; a later version may change what it does:

* The default shell for shots without a project shell: the SDK's `MaterialApp` with a `Material` surface, `material_ui`'s or `cupertino_ui`'s app widget when the project depends on that package, or a plain `WidgetsApp` when no design library is available. It changes when the SDK's Material and Cupertino, announced for deprecation, go.
* A preview's `theme`: applied through `PreviewThemeData`, an interface Flutter documents as not stable.
* [google_fonts](https://pub.dev/packages/google_fonts): fonts are downloaded once into `.dart_tool/shutter/fonts/google_fonts/` and served to the shot; a font that cannot be downloaded makes the shot an error instead of rendering in another font. Failures are recognised from the package's own messages, which change between its versions.

Details live in [`doc/manual.md`](doc/manual.md) (`shutter manual`).
