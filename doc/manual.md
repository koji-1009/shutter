# shutter manual

## What shutter shoots

Shutter renders widgets to PNG and compares two runs, so a visual change can be shown as before and after images.
The subjects are the widgets of the preview files you name: a preview file imports any widget of the app (it needs no annotation of its own) and returns it from a function annotated with Flutter's `@Preview`.
`@Preview` describes one widget with its wrapper, theme, size, brightness, text scale, and localizations.
Flutter's previewer (`flutter widget-preview start`) mounts it the same way but has no way out as an image; shutter gives it one.

* `shot <preview-file>...`: the previews in the named files.
* `shot --widget '<expression>'`: one Dart expression of type `Widget`, with `--import` naming the files it needs imported and `--size` its logical size, for a look without a file.

Shutter keeps no golden images, no catalogue, and no git knowledge.
Every comparison is between two runs you made, so there is no environment drift to manage and no update ritual.

## Where previews come from

`shot` takes any file under `lib/` with `@Preview` functions (Flutter's `@Preview` works only under `lib/`), so previews the project already has are named as they are.
New preview files go in the preview dir, which also holds `shell.dart`: `lib/preview/` for apps and `lib/src/preview/` for packages (off the public API surface).
A project counts as a package unless its `pubspec.yaml` says `publish_to: none`; an existing `lib/src/preview/` always wins.
Preview files are committed: the same subjects are shot before and after a change, and stay as the viewfinder in Flutter's previewer.
`shot` shoots only the files it is given.
A path is relative to the working directory (or absolute); a named file without a `@Preview` stops the shot with exit 66.

### How previews are found

* The named files are resolved with the analyzer, against the Dart SDK inside the Flutter SDK and the project's package config (so `pub get` must have run).
* Candidates are annotated public top-level functions, public static methods, and public constructors (generative ones only in classes that can be instantiated: not `abstract`, not `sealed`).
* An annotation is a preview when it evaluates to a `Preview` or `MultiPreview` (or a subclass); other annotations are ignored.
* Generated code rebuilds the annotation with every name it uses reached through an import prefix: the library's own import that provides the name (conditional configurations kept), the library itself for its own declarations, or the declaring library. So names bind as in the source, whatever the library shadows or prefixes, and static members of the enclosing class are qualified with the class name.
* A part file cannot be named (exit 64); name its library file.
* These candidates become `error` shots without being compiled: an annotation that does not resolve or has an error (the analyzer's message), and one naming a private declaration.
* When the generated test does not compile, every shot is an `error` shot carrying the first compiler error.

## One widget without a file

`--widget` is shot instead of preview files: nothing under `lib/` is scanned, and nothing is written to the project outside `.dart_tool/shutter/`.
The generated test imports `package:flutter/widgets.dart` and every `--import`, and shoots the expression as a `Preview` named after it, sized by `--size`; without `--size` the widget is shot at its own size.
An `--import` path is relative to the working directory (or absolute) and must be under `lib/`; `package:` URIs pass through.
The shot id hashes the expression and the resolved imports, so the same `--widget` and `--import` give the same id in every run, from any working directory; `--size` does not change the id.
A widget expression that does not compile is an `error` shot carrying the compiler message; it has no `file` or `at`.
`--widget` and preview files cannot be combined in one shot.

## Drawing model

The engine renders each preview in a `flutter_test` binding, one frame, no interaction.
State comes from the widget's construction expression; a widget that fetches or builds state internally can only be shot in the state it reaches on its own.

Per preview, from the outside in:

1. Shell: `shell(child)` from the `--shell` file, else from `<preview dir>/shell.dart` when the project has one, when the preview has no `wrapper`; otherwise the default shell (see Experimental).
2. `Localizations` when the preview sets `localizations`.
3. The preview at the top left.
4. The captured region: `SizedBox(size)`, then `theme.apply`, then `wrapper`, then the preview.

The PNG holds what is painted inside the captured region, and nothing outside it: the shell's surface lies outside, so where the preview paints no background the PNG is transparent, and the viewer's own background shows through.
A screen with a `Scaffold` paints its own; a widget is shot on no background, since shutter cannot know where the app places it.
To shoot a widget on the surface it sits on, paint it inside the preview: a `wrapper`, or a `ColoredBox` or `Material` around the widget in the preview function.

The project's shell replaces the default one entirely, so it decides what surrounds every shot: a Material surface (what `shutter init` writes, and what widgets such as `ListTile` or `TextField` need), a `CupertinoApp`, or a `WidgetsApp` with the app's own design system.
Shutter adds no design library to a shell without one.

`<preview dir>/shell.dart` is the default because it is committed: every clone and CI shoot with the same ambient.
A shell made for one task and not meant to be committed goes under `.dart_tool/`: `shutter init --shell .dart_tool/shutter/shell.dart` writes it there, `shutter shot --shell .dart_tool/shutter/shell.dart` shoots with it, and `shutter doctor --shell` checks it.
`--shell` takes any path; a shell outside `lib/` is imported by its file URI, so it imports the app with `package:` URIs.
Each run records its shell file in `manifest.json`, with the sha256 of its bytes (not of the files it imports).

Viewport: `size` when both dimensions are finite; a missing or infinite dimension uses 800×600 logical pixels.
The captured region takes a finite dimension of `size` as it is.
Without a finite width, the preview takes its own width, up to the viewport's, as on a screen.
Without a finite height, the preview gets unbounded height, as in a scrolling list, and is shot at its own height, even past the viewport: `Size(360, double.infinity)` shoots a widget 360 wide at the height it has in a list.
A widget that needs a bounded height (a `Scaffold`, a `ListView`, an `Expanded` in a `Column`) fails there; give it a finite height.
`brightness` sets the platform brightness and `textScaleFactor` the platform text scale, so the shell's app widget picks them up as on a device.
Images render at a device pixel ratio of 2.
Elevation paints its shadow as on a device; `flutter_test` would draw a solid outline in its place.

Fonts: every family in the project's `FontManifest.json` (pubspec `fonts:`, package fonts, MaterialIcons) plus Roboto from the Flutter SDK cache.
The test engine has no system font fallback, so a glyph missing from the style's fonts would render as a box. As on a device, shutter falls back to the host's CJK and emoji fonts: Hiragino Sans W3/W6 and Apple Color Emoji on macOS, Noto Sans CJK and Noto Color Emoji on Linux, Yu Gothic and Segoe UI Emoji on Windows. They are appended as `fontFamilyFallback` to the ambient default text style, and to the text theme of every design library whose theme the shell provides (SDK or package); text whose glyphs exist in its own font renders unchanged.
Cupertino text names the system font through the families `CupertinoSystemText` and `CupertinoSystemDisplay`, which the test engine does not resolve. On a macOS host they get SF Pro from `/System/Library/Fonts/`, as a macOS app does and as iOS draws; on other hosts, Roboto, the Android system font.
Host fonts come from the machine that shoots, so compare runs made on the same machine.

Settling: `Image` widgets are precached, then one `pump(settle)` (`--settle`, default 300 ms). `pumpAndSettle` is never used, because a loading indicator never settles.

HTTP is blocked by the test binding. A `NetworkImage` fails and the shot is `error`.

Errors (exceptions, overflows, failed image loads) do not stop the run.
The first one becomes the shot's `error`, and the first `lib/` location in its report becomes `at` (never generated code under `.dart_tool/shutter/`). For an image that fails to load, `at` is where the failing `Image` widget is created; when the report names no `lib/` location, `at` is the preview.
The PNG is still written when the frame was painted: overflow stripes are evidence.
A shot is also `error` when nothing was painted (a shell or wrapper that does not build its child), and when it never finished (a timeout, or the test process exiting); `at` then points at the preview.

## Experimental

Behaviour whose specification is not settled: a later version may change what it does.

### Default shell and design libraries

Material and Cupertino are moving out of the Flutter SDK (`package:flutter/material.dart`, `package:flutter/cupertino.dart`) into the `material_ui` and `cupertino_ui` packages, whose types are distinct from the SDK's.
The SDK's copies are announced for deprecation; the default shell below changes when they go.
Shutter's harness depends on neither; `.dart_tool/shutter/test/<run-id>/shutter_design.dart` is written for the libraries present: the SDK's copies while the SDK has them, and the packages when the project resolves them.

The default shell follows the project's direct `dependencies:`:

| project depends on   | default shell                                         |
| -------------------- | ----------------------------------------------------- |
| `material_ui`        | its `MaterialApp(home: Material(child: child))`       |
| `cupertino_ui`       | its `CupertinoApp(home: child)`                       |
| neither              | the SDK's `MaterialApp(home: Material(child: child))` |
| neither, no SDK copy | `WidgetsApp` with black default text                  |

`shutter init` writes `shell.dart` against the same library.

### Preview `theme`

A preview's `theme` is applied through `PreviewThemeData.apply`, which Flutter documents as "not stable and **will change**" (`package:flutter/widget_previews.dart`); shutter follows the interface as it changes.

### google_fonts

Shutter recognises a font google_fonts failed to load from the package's error and log text, which changed in google_fonts 8.2; what is supported may change with the package.
The package's public `GoogleFonts.pendingFonts()` cannot replace this: under `flutter test` the load fails within the first frame, and a failed load leaves the pending set once it completes.

When the project depends on `google_fonts`, its fonts are rendered as on a device without network access during the shot.
google_fonts looks for a font among bundled assets, then in a device cache, then fetches it over HTTP, which the test binding blocks.
Shutter serves the files it has cached in `.dart_tool/shutter/fonts/google_fonts/` as bundled assets and registers them before the first frame.
A font missing from that cache makes google_fonts fail during the shot (reported as an error, or, from google_fonts 8.2, only printed); shutter downloads every file named by those failures from `fonts.gstatic.com` (checking length and sha256 against the google_fonts package the project resolves), then shoots again.
A font that cannot be downloaded (offline, unknown file) leaves the shot `error`, naming the font, with `at` pointing at the preview; the text is never silently drawn in another font.
Downloads need network access once per font; keep `.dart_tool/shutter/fonts/` (for example as a CI cache) to shoot offline afterwards.
Projects that set `GoogleFonts.config.allowRuntimeFetching = false` are handled the same way: the missing asset name is looked up and downloaded.
Fonts bundled in the project's assets are used as they are.

## Limitations of the flutter_test engine

These come from rendering through `flutter test`.

* One frame, no interaction: taps, hovers, scrolling, and mid-animation states are not shot.
* HTTP is blocked, so network images fail to load.
* `flutter test` runs the engine with test fonts, which has no system font fallback. Shutter's host fonts are added to the text themes and the default text style, so a text style that sets its own `fontFamilyFallback` does not get them. google_fonts styles do this: glyphs outside the Google font (for example Japanese in a Latin-only font) render as boxes, where a device would fall back to a system font.

## Engine

The engine is the only layer that knows how PNGs are made.
v1 (`flutter_test`) writes `.dart_tool/shutter/test/<run-id>/shutter_test.dart`, a harness, the design library adapters, and one helper library per source library (or one for `--widget`), runs `flutter test` on that path, and deletes the directory.
Each run has its own directory, so shots running at the same time do not overwrite each other's code.
The project gains no dependency; `flutter_test` in `dev_dependencies` is enough.
When Flutter ships a capture command in the previewer itself, it replaces v1 without changing runs or diffs.

## Runs

`.dart_tool/shutter/runs/<run-id>/` holds `<id>.png` per shot and `manifest.json` (`run`, `shell` when a shell file was used, `shots`).
`<run-id>` is the UTC time of the shot (`20260918T101530Z`), suffixed `-2`, `-3`, ... when taken; a hidden `.<run-id>` file claims the name, so runs started in the same second get distinct ids.
`shot` prints the run directory as `run:`; `diff` accepts a run's directory, its id, `latest` for the newest run, or `latest~N` for the run N before it.
`latest` counts runs in id order (time, then suffix) and skips a run still being shot, whose `manifest.json` is not written yet.

`.dart_tool/shutter/` is ignored by git with the rest of `.dart_tool/`; shutter writes nothing else into the project.
Runs, diff images, and downloaded google_fonts accumulate there until you delete it; `flutter clean` deletes it with `.dart_tool/`.

### Ids

A shot id has a static and a runtime part joined by `.`.
The static part is the first 16 hex of `sha256("<file>|<symbol>|<annotationIndex>")`: the project-relative file, the symbol (`fn`, `Class.method`, `Class.new`, `Class.named`), and the annotation's position among all annotations on the declaration.
The runtime part is the index of the `Preview` produced by `transform()` (always `0` for a plain `Preview`).
Renaming a function, moving it to another file, or inserting an annotation before `@Preview` changes the id; `diff` then reports `removed` + `added`.

## Diff

`shutter diff <run-a> <run-b>` matches shots by id:

| status      | meaning                                                                                                    |
| ----------- | ---------------------------------------------------------------------------------------------------------- |
| `changed`   | the shot's status or error message differs, only one side has an image, sizes differ, or any pixel differs |
| `added`     | only in run b                                                                                              |
| `removed`   | only in run a                                                                                              |
| `unchanged` | otherwise                                                                                                  |

An error is part of what was shot: the same error with the same image on both sides is `unchanged`, and every entry carries its shot's `error` and `at`.
An entry carries the size of its after shot (the before shot for `removed`); a `changed` entry whose size changed also carries `before_size`.
Byte-identical PNGs are unchanged; otherwise pixels are compared as exact RGBA on the union of both canvases, and `diff_ratio` records the share that differs.
Each entry points at its `before` / `after` PNGs inside the two run directories; no image is copied and nothing is written.
With `--images`, each `changed` entry with both images also gets `<id>.png` in `.dart_tool/shutter/diffs/<diff-id>/`: the before image faded, differing pixels in red.
When the two runs were shot with different shells (path or sha256), `shell` shows each run's (`default` for the default shell): a shell change alters every image without any widget changing. The entries are compared as always.

## Output

`shot` and `diff` print YAML starting with the comment `# shutter ai-report v1`, with absolute paths to open.
`shot` gives `run`, `shell` (the shell file with its sha256, or `default`), `summary`, and `shots`, errors first.
`diff` gives `diff` (with `--images`), `before`, `after`, `shell` (when the shells differ), `summary`, and `entries` in the order changed → added → removed → unchanged.

## Exit codes

| command  | 0               | 1              | 2                |
| -------- | --------------- | -------------- | ---------------- |
| `shot`   | every shot ok   | —              | any shot `error` |
| `diff`   | no difference   | differences    | —                |
| `doctor` | no failed check | a failed check | —                |

Other failures follow sysexits: 64 usage, 66 missing run or file, 69 no Flutter SDK, 70 internal error, 78 project not usable.

## Commands

| command  | purpose                                                                                                                   |
| -------- | ------------------------------------------------------------------------------------------------------------------------- |
| `agent`  | the step-by-step playbook                                                                                                 |
| `manual` | this document                                                                                                             |
| `doctor` | SDK version, font cache, shell (`--shell`)                                                                                |
| `init`   | write `shell.dart` (`--shell`)                                                                                            |
| `shot`   | render the named preview files, or one `--widget`, into a new run (`--widget`/`--import`/`--size`, `--settle`, `--shell`) |
| `diff`   | compare two runs (`--images`)                                                                                             |
