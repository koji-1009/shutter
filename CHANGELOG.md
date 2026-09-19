# Changelog

## 0.1.0

Initial release.

* `shutter shot <preview-file>...` renders the widgets of the named preview files to PNG. A preview file imports any widget of the app, which needs no annotation of its own, and returns it from a function annotated with Flutter's `@Preview`.
* `shutter shot --widget '<expression>'` renders one widget without a preview file (`--import` for the files it needs, repeatable; `--size` for its logical size), writing nothing to the project outside `.dart_tool/shutter/`.
* Shots render through a generated `flutter_test` file with the project's fonts, a project-wide `shell.dart` that replaces the default shell, and a fixed `--settle` pump. The project gains no dependency; `flutter_test` in `dev_dependencies` is enough.
* Errors and overflows are recorded per shot with a `lib/` location, and the rest of the run continues. A shot that never finishes or paints nothing is an `error` shot.
* Concurrent shots in one project get separate run and test directories.
* `shutter diff` compares two runs by shot id as `changed`, `added`, `removed`, or `unchanged`, in pure Dart. An error counts as part of the shot; byte-identical PNGs are unchanged, and otherwise any differing pixel makes the shot `changed`. `--images` adds an image marking the differing pixels of each changed shot. A run is named by its directory, its id, `latest`, or `latest~N`.
* `shot` and `diff` print YAML starting with `# shutter ai-report v1`, with absolute image paths.
* `shutter init` writes a `shell.dart` against the design library the project uses.
* `--shell <file>` on `shot`, `init`, and `doctor` names a shell outside the preview dir, such as one under `.dart_tool/` that is not committed. Each run records its shell file and its sha256, and `diff` shows both runs' shells when they differ.
* `shutter agent` and `shutter manual` print the playbook and the reference from the binary; `shutter doctor` checks the Flutter SDK version, its font cache, and the shell.
* An agent skill, `skills/shutter-visual-check/`, for `dart run skills add` / `get`: when to use shutter, pointing at `shutter agent`.
* Host fonts: CJK and emoji text falls back to the host's system fonts; Cupertino text renders in SF Pro on macOS hosts and Roboto elsewhere.
* Requires Flutter 3.47+ (Dart 3.13+) in the target project.

Experimental (specification not settled):

* A default shell generated for the design library the project uses: the SDK's Material, `material_ui`, `cupertino_ui`, or a plain `WidgetsApp` when none is available.
* A preview's `theme`, through Flutter's unstable `PreviewThemeData` interface.
* google_fonts: files are downloaded once into `.dart_tool/shutter/fonts/google_fonts/`, verified, and served as bundled assets. A font that cannot be obtained makes the shot an error.
