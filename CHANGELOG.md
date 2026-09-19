# Changelog

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
