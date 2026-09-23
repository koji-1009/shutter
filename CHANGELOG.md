# Changelog

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
