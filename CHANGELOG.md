# Changelog

## Unreleased

Host fallback fonts in text whose style keeps them out.

* CJK and emoji in a `CupertinoAlertDialog` rendered as boxes in a shot reported `ok`: their text styles inherit nothing and name the Cupertino system font, so the host fonts added to the default text style and the themes never reached them. The host fonts are now appended to the text of every paragraph and text field before each layout.
* Text in a style with its own `fontFamilyFallback`, such as google_fonts', now falls back to the host fonts too; Japanese in a Latin-only Google font rendered as boxes.
* Text in a package font's style falls back as well.
* A character the host's CJK and emoji fonts do not draw falls back to a host font that draws it, picked by what each font in the host's font directories draws: Hangul, Thai, Arabic, Devanagari, Tamil, Khmer, or any other script the host has a font for. Before, only Hiragino and Apple Color Emoji were loaded on macOS, and the rest rendered as boxes. A run that meets such a character shoots again with the font, and the project keeps it in `.dart_tool/shutter/fonts/host/` for later runs. Text that rendered before renders unchanged.
* The manual and the agent playbook say where the host fonts do not reach: text a widget paints itself, such as a `Slider`'s value indicator, under a `Theme` built in a `wrapper` or the preview function. A theme given through the preview's `theme` reaches it.

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
