# Changelog

## Unreleased

The device a shot is drawn as.

* `shutter shot --pixel-ratio <ratio>` (and `semantics`, and `shot(pixelRatio:)`) draws every preview at that device pixel ratio instead of 2: the PNG is the shot's logical size times the ratio, and what reads the ratio, such as `MediaQuery.devicePixelRatioOf` and an `AssetImage` picking its variant, follows it as on the device. `shot` prints it, `manifest.json` records it, `diff` prints both runs' when they differ and returns it as `ShotSetup.pixelRatio`. It is not part of shot ids.

## 1.3.0

Shutter as a Dart library.

* `package:shutter/shutter.dart` exposes `shot`, `diff`, `doctor`, and `prune`, so another Dart tool shoots without starting a process or reading the YAML report. `shot` takes the project directory, relative to which every path is read, and the CLI's options as types: `PreviewFiles` or a `WidgetExpression` with its imports and a `LogicalSize` or `WidgetSize.unbounded`, `settle`, `shell`, `ShotAction`s, `PreviewCapture` or `ScreenCapture` with its viewport, a `Keyboard` and its tint, `networkImages`, `platform`, and `semantics`.
* `shot` returns the run's id and directory and each shot's id, status, name, file and line, size, PNG path, error, and `at`. A shot that fails to render is a `ShotStatus.error` shot; a run that cannot be shot throws a `ShutterException` with the exit code the CLI would use. Every argument, result, and progress event compares by value and prints what it holds.
* `onProgress` receives the scan of the preview files, each `flutter test` run, each shot as its test finishes, and each google_fonts download, each with a line for a log.
* A `shot` of the same project again in one process keeps the analysis of its preview files and reads again only the files that changed since, so a tool shooting many times no longer resolves Flutter for each shot.
* `diff` compares two runs as `shutter diff` does, naming each by directory, id, `latest`, or `latest~N`, with the images and a `DiffComposite` (direction and title) as arguments. It returns both run directories, what each was shot with (shell, actions, capture, keyboard, network images, semantics, platform), and each shot id's status, shot, diff ratio, earlier size, and the absolute paths of its before, after, diff, and composite images. A title that could not be drawn, or does not fit one line, is a warning in the result.
* `doctor` returns the checks of `shutter doctor` as `DoctorCheck`s, each with its `CheckLevel` (`ok`, `warn`, `fail`), what was found, and what to do about it: the Flutter SDK and its version, its font cache, the project, and its shell.

## 1.2.0

Shots drawn as iOS, a `--widget` at its own size, and a way to clear old runs.

* `shutter shot --platform ios` (and `semantics`) draws every preview as iOS instead of Android, the platform `flutter test` runs as: `defaultTargetPlatform` is `iOS` while each preview is shot, so a theme without its own `platform`, the back button, page transitions, adaptive widgets, and the app's own `defaultTargetPlatform` checks draw as on an iPhone. `shot` prints it, `manifest.json` records it, and `diff` prints both runs' when they differ. It is not part of shot ids.
* `shutter shot --widget <expression> --size unbounded` lays the widget out with neither dimension bounded and shoots it at its own size, however wide; without `--size`, its width still stops at the viewport's 800.
* `shutter prune --keep <n>` deletes every run under `.dart_tool/shutter/runs/` but the newest n, and prints the run directories it removed and kept. A run still being shot is left as it is.

## 1.1.1

Host fallback fonts for any script the host has a font for, and in text whose style keeps them out.

* CJK and emoji in a `CupertinoAlertDialog`, and in a style with its own `fontFamilyFallback` such as google_fonts', rendered as boxes in a shot reported `ok`; they now fall back to the host fonts.
* Scripts beyond CJK and emoji rendered as boxes too. Every run now loads the host's UI font and its fonts for Simplified Chinese, Hangul, Thai, Arabic, Hebrew, and Devanagari, and a character none of those draw falls back to a host font that draws it.
* The manual and the agent playbook say where the host fonts do not reach: text a widget paints itself, such as a `Slider`'s value indicator, under a `Theme` built in a `wrapper` or the preview function.

## 1.1.0

The semantics tree as an image.

* `shutter semantics` takes the same preview files, `--widget`, and options as `shot` (except `--keyboard-tint`) and draws each shot's semantics tree instead of what the app paints, as Flutter's `SemanticsDebugger` draws it: a box per node with its label and what it is or does. The PNG has the size of the `shot` PNG, and `diff` compares two such runs as any others, so a change to what TalkBack and VoiceOver read shows when the pixels do not change.
* A `semantics` run records `image: semantics` in `manifest.json`; `semantics` prints it, and `diff` prints both runs' `image` when they differ. It is not part of shot ids.
* The `shutter-visual-check` skill also covers changes to what assistive technology reads.

## 1.0.0

Network images, from files fetched beforehand, and the on-screen keyboard's area in a color.

* `shutter shot --network-image <url>=<file>` (repeatable) serves the file to a `NetworkImage` that requests the URL, which `flutter test` otherwise answers with 400. A URL that is not served still fails, so a missed image stays an `error` shot. Only what `NetworkImage` fetches is served; other HTTP clients such as `package:http` are not.
* `shot` prints each URL with its file and sha256, `manifest.json` records them, and `diff` prints both runs' when they differ. They are not part of shot ids.
* `shutter shot --keyboard-tint <color>` (experimental, with `--keyboard`) paints the keyboard's area in the color, given as `RRGGBB` or `AARRGGBB`: over what the app paints there in either capture, and over menus and dialogs with `--capture screen`. It only paints; actions reach the app under it. `shot` prints it, `manifest.json` records it, and `diff` prints both runs' when they differ.

## 0.2.2

One image per change: before, diff and after on a single sheet.

* `shutter diff --composite` writes `<id>-composite.png` per entry into `.dart_tool/shutter/diffs/<diff-id>/`, next to what `--images` writes: the before, diff and after panels on the union canvas of the two shots, each under a caption naming it and, when the two sides differ in size, its own size. The entry points at it as `composite`.
* `--direction horizontal` puts the three panels side by side, `vertical` stacks them, and the default `auto` puts a portrait shot side by side and a landscape one stacked, so that all three stay in one view whatever the subject's shape. The panels are never scaled; `--images` stays the 1:1 view of the marked diff.
* An entry with an image on one side only gets a sheet too, its absent panel left as background and its diff panel all red: a widget the edit broke, or one whose id the edit changed, is shown rather than left out. An entry whose two PNGs are identical gets none.
* `--title <text>` draws a line of text above the panels. It is rendered through the engine rather than drawn from a bundled bitmap font, so any script the host has a font for works, and it is laid out in exactly the room each size of sheet leaves between its gutters, at the size of that sheet's captions. A title that did not fit one line is reported on stderr with the width of the sheets it did not fit.
* `--title` is the only part of `diff` that needs a Flutter SDK, and costs one `flutter test` run per distinct sheet size. Without it, `diff` stays pure Dart.
* The diff directory is created, and reported as `diff`, for either `--images` or `--composite`.

## 0.2.1

The layout of a screen while its on-screen keyboard is up.

* `shutter shot --keyboard <height>` (experimental) lays every preview out as a device does while its on-screen keyboard is up: the view reports a bottom inset of that many logical pixels (`MediaQuery.viewInsets`) from the first frame. A `Scaffold`, or any layout reading the inset, makes room for the keyboard; the keyboard itself is not drawn. There is no default height.
* `shot` prints the height, `manifest.json` records it, and `diff` prints both runs' when they differ. It is not part of shot ids.

## 0.2.0

States that come from a gesture or typing, and what opens above a preview.

* `shutter shot --tap` and `--enter <target>=<text>` (repeatable, run in the order given), then one of `--press`, `--hover`, or `--focus`, act on every preview before the capture. A target is `key:<value>`, `text:<string>`, `label:<semantics label>` (a text field's label or hint, a button's text), or `type:<Widget>`; a target that matches no widget, several, or cannot be reached makes the shot an error. Each action is followed by `--settle` milliseconds drawn in 16 ms frames; `shutter agent` suggests `--settle 700` for the state after a tap, once its ink is over, and another `--settle` for another point of an animation.
* `shutter shot --capture screen` captures the whole viewport, with the shell's surface and the menus, dialogs, bottom sheets, and tooltips the app draws above the preview; `--viewport <width>x<height>` sets the viewport, the preview at its top left.
* `shot` prints the run's actions and capture, `manifest.json` records them, and `diff` prints both runs' when they differ. They are not part of shot ids.
* The `shutter-visual-check` skill also covers pressed, hovered, focused, opened, and typed states.

## 0.1.1

Documentation and package metadata; the tool behaves as in 0.1.0.

* The package description, the README, and `shutter --help` open on what shutter produces, a change to a widget expressed as before and after images, instead of on the agent that drives it.
* The `ai` topic is replaced by `cli`: shutter is a command-line tool an agent can drive, not an AI package.
* README lists when to reach for shutter: a change going up for review, a refactor that should change nothing on screen, a widget that might break on screen, a dependency just added or upgraded.
* `shutter agent` says what `shot --widget` answers, a look at a widget before the call site exists, names the commands that upload an image to a pull or merge request, and states that `--import` reaches only what the project's `pubspec.yaml` resolves.
* Flutter's previewer is called by its name, the Flutter Widget Previewer.

## 0.1.0

Initial release: a CLI, shaped for AI agents, that renders Flutter widgets to PNG and compares two runs.

* `shutter shot` renders the `@Preview` functions of the named files, or one `--widget` expression, to PNG through `flutter test`. The target project gains no dependency.
* `shutter diff` compares two runs by shot id as `changed`, `added`, `removed`, or `unchanged`; `--images` marks the differing pixels.
* `shutter init` writes the shell that wraps every shot, and `shutter doctor` checks the setup.
* `shutter agent` and `shutter manual` print the playbook and the reference; the `shutter-visual-check` skill points agents at them.
* Requires Flutter 3.47+ (Dart 3.13+) in the target project.

Experimental (specification not settled):

* The default shell generated for the design library the project uses.
* A preview's `theme`, through Flutter's unstable `PreviewThemeData` interface.
* google_fonts, downloaded once into `.dart_tool/shutter/fonts/google_fonts/` and served as bundled assets.
