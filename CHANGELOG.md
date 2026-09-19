# Changelog

## 0.1.1

Documentation and package metadata; the tool behaves as in 0.1.0.

* The package description, the README, and `shutter --help` open on what shutter produces, a change to a widget expressed as before and after images, instead of on the agent that drives it.
* The `ai` topic is replaced by `cli`: shutter is a command-line tool an agent can drive, not an AI package.
* README lists when to reach for shutter, including a look at a widget before the call site exists (`shot --widget`).
* `shutter agent` names the commands that upload an image to a pull or merge request, and states that `--import` reaches only what the project's `pubspec.yaml` resolves.
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
