# shutter — agent playbook

Shutter closes a visual change with an image: it renders the widgets of the preview files you name to PNG, compares two runs, and gives you the images to attach to the PR.
It makes no judgement; what to shoot, how to prepare the before state, whether a change is good, and where to post are your decisions.

## Before and after

 1. First time: `dart install shutter && shutter doctor`. Without a preview dir or `shell.dart`, run `shutter init`.
 2. Before editing, decide what to shoot. `grep` for where the widget is used; shoot the screens that contain it too when a change can break their layout.
 3. Find the preview files that already show each subject; for a subject without one, write a preview file in the preview dir (below). Any widget can be a subject: it needs no annotation of its own, only an import.
 4. `shutter shot <preview-file>...`, naming the preview files of step 3: the before run. Preparing the before state is up to you: shoot before editing, `git stash` and shoot, or shoot in a `git worktree`.
 5. Edit.
 6. `shutter shot <preview-file>...` with the same files: the after run.
 7. `shutter diff latest~1 latest` when the two shots are the last two runs; otherwise `shutter diff <before-run> <after-run>`, with the `run:` directories the two shots printed.
 8. Open the `before` / `after` images of every `changed` entry and check them against your intent; `diff --images` adds a `diff` image marking the differing pixels. `unchanged` on something you edited means the edit did not reach the shot.
 9. The images are files under `.dart_tool/shutter/`; where to post them is up to you. A path alone renders nothing: `gh pr comment <number> --attach '<png>#<alt text>'` (gh 2.101+) uploads them into a GitHub comment, `glab mr note create <mr> --attach <png>` (glab 1.117+, experimental) into a GitLab one.
10. Keep the preview files: the next change is shot against the same subjects, and the Flutter Widget Previewer draws them too.

## Preview files

`shutter shot` takes any file under `lib/` with `@Preview` functions, so previews the project already has are named as they are.
New preview files go in the preview dir, `lib/preview/` (`lib/src/preview/` in a package). Import the widget you touched and return it from a function annotated with Flutter's `@Preview`:

```dart
// lib/preview/settings_page_preview.dart
import 'package:flutter/widget_previews.dart';
import 'package:flutter/widgets.dart';

import '../settings_page.dart';
import 'fakes.dart';

@Preview(name: 'SettingsPage / signed in', size: Size(390, 844))
Widget settingsSignedIn() => SettingsPage(user: fakeUser);

@Preview(name: 'SettingsPage / signed out', size: Size(390, 844))
Widget settingsSignedOut() => const SettingsPage(user: null);
```

* One function per state (empty, loading, error), with the state passed in through the constructor.
* Always set `size`: `390x844` for a screen; for a widget, its width and `double.infinity` as the height (`Size(360, double.infinity)`). The widget then gets unbounded height, as in a scrolling list, and the image has its own height before and after a change that grows it.
* Only what the preview paints is in the PNG; a widget without a background of its own is transparent there. To show it on the surface it sits on, wrap it in the preview (`ColoredBox`, `Material`, or `wrapper:`).
* `shutter shot` shoots only the files it is given: `shutter shot lib/preview/settings_page_preview.dart`.
* Top-level functions, static methods, and constructors without required arguments are all valid targets; `MultiPreview` and `Preview` subclasses work too.

## Shell

`shell.dart` in the preview dir wraps every shot without its own `wrapper`: set the app's themes, router, and providers there once.
It replaces shutter's default shell (experimental: a `MaterialApp` with a `Material` surface, from `material_ui` when the project depends on it; see `shutter manual`), so it decides what surrounds every shot: keep a `Material` around the child for Material widgets, use `CupertinoApp` for a Cupertino app, or `WidgetsApp` for an app with its own design system.
`shutter init` writes one against the design package the project depends on.
A preview with `wrapper:` is not wrapped in `shell()`; call `shell()` inside the wrapper when it needs the app's ambient.
The shell in the preview dir is committed and shared. When you need a shell only for the task at hand and it should not land in the commit, write it under `.dart_tool/` (`shutter init --shell .dart_tool/shutter/shell.dart`, importing the app with `package:` URIs) and pass the same `--shell` to every `shot` of the task.
`shot` prints the shell it used as `shell:` (`default` when there was none); check it before and after.
If `diff` prints `shell:`, the two runs were shot with different shells, and every image may differ for that reason alone.

## One widget without a preview file

For a quick look that does not need to be kept, pass the widget on the command line and name the project files it comes from with `--import`.
It answers "how does this render here" before a call site exists: a widget of a package the project depends on but you have never used, a screen through the project's shell, an API you are about to reach for.

```bash
shutter shot --widget 'PrimaryButton(label: "OK")' --import lib/ui/button.dart --size 200x56
```

* `--widget` is any Dart expression of type `Widget`; `--import` is a file under `lib/` (or a `package:` URI) it needs imported, repeatable. `package:flutter/widgets.dart` is always imported, so Material widgets need the Material library the project uses as an `--import` (`package:material_ui/material_ui.dart` or `package:flutter/material.dart`).
* Only that widget is shot, wrapped in the shell; nothing is written to the project outside `.dart_tool/shutter/`.
* The generated test is compiled inside the project, so `--import` reaches only what the project's `pubspec.yaml` already resolves: add the package first, then shoot it.
* Without `--size` the widget is shot at its own size; `--size` fixes both dimensions and stretches the widget to them.
* The same `--widget` and `--import` give the same shot id in every run, so before and after line up in `diff`.

## Exit codes

* `shot`: 0 all ok, 2 any error.
* `diff`: 0 no difference, 1 differences. 1 means "changed", not "failed".
