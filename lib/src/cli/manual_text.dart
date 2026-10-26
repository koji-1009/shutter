// Mirror of `doc/manual.md`, printed by `shutter manual`. Kept byte-identical by
// test/cli/text_parity_test.dart; edit the markdown, then copy it here.
const String manualText = r'''
# shutter manual

## What shutter shoots

Shutter renders widgets to PNG and compares two runs, so a visual change can be shown as before and after images.
The subjects are the widgets of the preview files you name: a preview file imports any widget of the app (it needs no annotation of its own) and returns it from a function annotated with Flutter's `@Preview`.
`@Preview` describes one widget with its wrapper, theme, size, brightness, text scale, and localizations.
The Flutter Widget Previewer (`flutter widget-preview start`) mounts it the same way but has no way out as an image; shutter gives it one.

* `shot <preview-file>...`: the previews in the named files.
* `shot --widget '<expression>'`: one Dart expression of type `Widget`, with `--import` for the files under `lib/` or `package:` URIs it needs and `--size` for the size it is shot at, for a look without writing a preview file.
* `semantics`: the same subjects, drawn as their semantics tree, what assistive technology reads (see The semantics tree).

Shutter keeps no golden images, no catalogue, and no git knowledge.
Every comparison is between two runs you made, so there is no environment drift to manage and no update ritual.

## Where previews come from

`shot` takes any file under `lib/` with `@Preview` functions (Flutter's `@Preview` works only under `lib/`), so previews the project already has are named as they are.
New preview files go in the preview dir, which also holds `shell.dart`: `lib/preview/` for apps and `lib/src/preview/` for packages (off the public API surface).
A project counts as a package unless its `pubspec.yaml` says `publish_to: none`; an existing `lib/src/preview/` always wins.
Preview files are committed: the same subjects are shot before and after a change, and the previewer draws them too.
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

## One widget without a preview file

`--widget` is shot instead of preview files: nothing under `lib/` is scanned, and nothing is written to the project outside `.dart_tool/shutter/`.
The generated test imports `package:flutter/widgets.dart` and every `--import`, and shoots the expression as a `Preview` named after it, sized by `--size`; without `--size` the widget is shot at its own size.
An `--import` path is relative to the working directory (or absolute) and must be under `lib/`; `package:` URIs pass through.
The shot id hashes the expression and the resolved imports, so the same `--widget` and `--import` give the same id in every run, from any working directory; `--size` does not change the id.
A widget expression that does not compile is an `error` shot carrying the compiler message; it has no `file` or `at`.
`--widget` and preview files cannot be combined in one shot.

## Actions

A state that comes from a gesture or from typing is shot by acting on the preview before the capture:

* `--tap <target>` taps the widget: a pointer down and up at its centre. Repeatable.
* `--enter <target>=<text>` enters the text into the text field the target is or holds (exactly one `EditableText`), as the platform's keyboard does: the field takes focus and its text is replaced. The target ends at the first `=`. Repeatable; taps and entries run in the order given.
* `--press <target>` holds a pointer down on it through the capture: its pressed state, with the ink the press has drawn by then.
* `--hover <target>` keeps a mouse pointer over it through the capture.
* `--focus <target>` gives it keyboard focus, highlighted as with a keyboard: `flutter_test` runs as a touch device, where focus draws no highlight. The node is the first focus node inside the widget (a button's or text field's own), else the one around it.
* At most one of `--press`, `--hover`, and `--focus`; it follows the taps and entries.

A target is `key:<value>` (a `ValueKey<String>`), `text:<string>` (a `Text` showing exactly that string, or an `EditableText` holding it), `label:<string>` (a widget whose semantics label is exactly that string: a text field's `labelText` or `hintText`, a button's text), or `type:<Widget>` (a widget of that type, with or without type arguments: `type:Checkbox`, `type:DropdownButton<String>`); offstage widgets do not count.
`label:` names a text field without a key: `--enter 'label:Email=example@example.com'`.
Each action is followed by `--settle` milliseconds drawn in 16 ms frames, as on a device, so `--settle` is also how long after an action the capture comes: an animation the action starts (ink, a check mark, a menu opening) is shot at that point of its course.
`flutter test` runs as Android, so Material 3 presses use `InkSparkle`: its sparkle shows from about 100 ms to about 600 ms of a press, then the flat pressed overlay stays, as on a device.

The actions apply to every preview of the run.
A preview is an `error` shot, without a PNG and with `at` pointing at the preview, when a target matches no widget or more than one, when a pointer at the target's centre does not reach it (covered, outside the viewport, or ignoring pointers), when an `--enter` target holds no text field or more than one, or when a `--focus` target cannot take focus.

The run records its actions in `manifest.json`; `shot` prints them, and `diff` prints both runs' when they differ, since they change every image without any widget changing.
They are not part of shot ids, so a run with actions pairs shot for shot with one without.

### Taps that navigate

A page is shot through a preview of its own: returned from a preview function, it is shot from its first frame, with an id of its own.
A tap that pushes a page covers the preview, which is then no longer painted: without `--capture screen` the shot is an `error` saying so.
With `--capture screen` the page is shot; its transition takes 450 ms (`flutter test` runs as Android), so `--settle 700` shoots it once it is in place.

## Capturing the screen

`--capture screen` captures the whole viewport instead of the captured region: the shell's surface, and what the app draws above the preview in its overlay, such as menus, dialogs, bottom sheets, and tooltips, which the captured region never holds.
The shot's size is the viewport's.
`--viewport <width>x<height>` sets the viewport, with the preview at its top left: give a small preview the room a menu or a dialog opens into.
Without it, the viewport is the drawing model's.
The run records the capture and the viewport as it does its actions.

## The semantics tree

`shutter semantics` takes the same preview files, `--widget`, and options as `shot`, except `--keyboard-tint`, and shoots the same way, actions included.
Instead of what the app paints, each PNG holds the app's semantics tree over the same region: the nodes TalkBack and VoiceOver read and act on, which a screenshot does not show.
A change that leaves the pixels as they were but changes what is read, such as a button wrapped in `ExcludeSemantics`, is `unchanged` between two `shot` runs and `changed` between two `semantics` runs.

The tree is drawn as Flutter's `SemanticsDebugger` draws it; the debugger's painter is private, so shutter draws the same:

* A white box per node, framed in a color from its index among its siblings and its depth, the frame thicker the higher the node is in the tree.
* In the box, its tooltip and label, then what it is or does: `checked` or `unchecked`, `textfield`, `button`, `disabled`, `long-pressable`, `scrollable`, `adjustable`. The text is centred at 10 logical pixels, wrapped to the box's width, and cut to the box.

What the debugger does not write is not in the image: a node's value (the text in a field) and hint, and flags such as a header.
Frame widths follow the depth of the whole tree, and colors a node's place among its siblings, so a node inserted before others, or a branch made deeper, redraws nodes whose own semantics did not change.

The whole tree of the view is drawn and cut to the captured region (the viewport with `--capture screen`), so its nodes are the app's own, merged as the app merges them, and the shell's nodes that enclose the preview frame its edges.
The PNG has the size of the `shot` PNG of the same preview and options, so the two can be set side by side.
The run records `image: semantics` in `manifest.json`; `semantics` prints it, and `diff` prints both runs' `image` when they differ.
It is not part of shot ids, so compare a `semantics` run with another `semantics` run.

## Drawing model

The engine renders each preview in a `flutter_test` binding: one frame, then the run's actions, then the capture.
State comes from the widget's construction expression or from the actions; a widget that fetches or builds state internally can only be shot in the state it reaches on its own.

Per preview, from the outside in:

1. Shell: `shell(child)` from the `--shell` file, else from `<preview dir>/shell.dart` when the project has one, when the preview has no `wrapper`; otherwise the default shell (see Experimental).
2. `Localizations` when the preview sets `localizations`.
3. The preview at the top left.
4. The captured region: `SizedBox(size)`, then `theme.apply`, then `wrapper`, then the preview.

The PNG holds what is painted inside the captured region (the whole viewport with `--capture screen`), and nothing outside it: the shell's surface lies outside, so where the preview paints no background the PNG is transparent, and the viewer's own background shows through.
A screen with a `Scaffold` paints its own; a widget is shot on no background, since shutter cannot know where the app places it.
To shoot a widget on the surface it sits on, paint it inside the preview: a `wrapper`, or a `ColoredBox` or `Material` around the widget in the preview function.
The same holds for ink: a press, hover, or focus is drawn on the nearest `Material` above the widget, which for a widget without its own (an `InkWell`, a `ListTile`) is the shell's surface; a `Material` in the preview brings it into the PNG.

The project's shell replaces the default one entirely, so it decides what surrounds every shot: a Material surface (what `shutter init` writes, and what widgets such as `ListTile` or `TextField` need), a `CupertinoApp`, or a `WidgetsApp` with the app's own design system.
Shutter adds no design library to a shell without one.

`<preview dir>/shell.dart` is the default because it is committed: every clone and CI shoot with the same ambient.
A shell made for one task and not meant to be committed goes under `.dart_tool/`: `shutter init --shell .dart_tool/shutter/shell.dart` writes it there, `shutter shot --shell .dart_tool/shutter/shell.dart` shoots with it, and `shutter doctor --shell` checks it.
`--shell` takes any path; a shell outside `lib/` is imported by its file URI, so it imports the app with `package:` URIs.
Each run records its shell file in `manifest.json`, with the sha256 of its bytes (not of the files it imports).

Viewport: `--viewport` when given; else `size` when both dimensions are finite; a missing or infinite dimension uses 800×600 logical pixels.
The captured region takes a finite dimension of `size` as it is.
Without a finite width, the preview takes its own width, up to the viewport's, as on a screen.
Without a finite height, the preview gets unbounded height, as in a scrolling list, and is shot at its own height, even past the viewport (with `--capture screen`, the PNG stops at the viewport): `Size(360, double.infinity)` shoots a widget 360 wide at the height it has in a list.
A widget that needs a bounded height (a `Scaffold`, a `ListView`, an `Expanded` in a `Column`) fails there; give it a finite height.
`brightness` sets the platform brightness and `textScaleFactor` the platform text scale, so the shell's app widget picks them up as on a device.
Images render at a device pixel ratio of 2.
Elevation paints its shadow as on a device; `flutter_test` would draw a solid outline in its place.

Fonts: every family in the project's `FontManifest.json` (pubspec `fonts:`, package fonts, MaterialIcons) plus Roboto from the Flutter SDK cache.
The test engine has no system font fallback, so a glyph missing from the style's fonts would render as a box. As on a device, shutter falls back to the host's fonts.
Every run loads a fixed list of the host's fonts, in this order: CJK and emoji, then the UI font and the fonts for Simplified Chinese, Hangul, Thai, Arabic, Hebrew, and Devanagari.
On macOS these are Hiragino Sans W3/W6, Apple Color Emoji, SF Pro, Hiragino Sans GB, Apple SD Gothic Neo, Thonburi, SF Arabic, SF Hebrew, and Kohinoor; on Linux, Noto Sans CJK, Noto Color Emoji, and Noto Sans (Thai, Arabic, Hebrew, Devanagari); on Windows, Yu Gothic, Segoe UI Emoji, Segoe UI (with Arabic and Hebrew), Microsoft YaHei, Malgun Gothic, Leelawadee UI, and Nirmala UI.
A Han character takes the Japanese form when the CJK font has it.
For a character of a paragraph or text field that neither these nor the text's own fonts draw, shutter picks a host font that does, by what each font in the host's font directories draws (its `cmap`): the font nearest the regular weight, then in the earliest directory, then drawing the fewest characters, a font for that script.
A picked font is loaded for every weight, and of a collection (`.ttc`) only its first font, so a collection whose first font is black would render the script black at any weight.
The run shoots again with the fonts picked.
They last for that run only, so the same text renders with the same fonts in every run; what each host font draws is kept in `.dart_tool/shutter/fonts/host/`.
The fallback fonts are appended as `fontFamilyFallback` to the ambient default text style, and to the text theme of every design library whose theme the shell or the preview's `theme` provides (SDK or package); text whose glyphs exist in its own font renders unchanged.
Each frame, before layout, they are also appended to the text of every paragraph and text field, so text whose style keeps them out falls back too: a style that inherits nothing, such as a `CupertinoAlertDialog`'s, or one with its own `fontFamilyFallback`, such as google_fonts'.
Cupertino text names the system font through the families `CupertinoSystemText` and `CupertinoSystemDisplay`, which the test engine does not resolve. On a macOS host they get SF Pro from `/System/Library/Fonts/`, as a macOS app does and as iOS draws; on other hosts, Roboto, the Android system font.
Host fonts come from the machine that shoots, so compare runs made on the same machine.

Settling: `Image` widgets are precached, then one `pump(settle)` (`--settle`, default 300 ms); after each action, `--settle` ms more in 16 ms frames. `pumpAndSettle` is never used, because a loading indicator never settles.

HTTP is blocked by the test binding. A `NetworkImage` fails and the shot is `error`, unless `--network-image` serves its URL (see Network images).

Errors (exceptions, overflows, failed image loads) do not stop the run.
The first one becomes the shot's `error`, and the first `lib/` location in its report becomes `at` (never generated code under `.dart_tool/shutter/`). For an image that fails to load, `at` is where the failing `Image` widget is created; when the report names no `lib/` location, `at` is the preview.
The PNG is still written when the frame was painted: overflow stripes are evidence.
A shot is also `error` when nothing was painted (a shell or wrapper that does not build its child), and when it never finished (a timeout, or the test process exiting); `at` then points at the preview.

## Network images

The test binding answers every HTTP request with status 400, so an `Image.network` never gets its image.
`shot --network-image <url>=<file>` serves a file you fetched beforehand for that URL: a `NetworkImage` that requests the URL gets the file's bytes, as if the server had sent them, and is drawn as on a device.

```bash
curl --create-dirs -o .dart_tool/shutter/images/avatar.png https://example.com/avatar.png
shutter shot lib/preview/profile_preview.dart --network-image https://example.com/avatar.png=.dart_tool/shutter/images/avatar.png
```

* The URL ends at the last `=`, so a query keeps its own: `'https://example.com/a.png?w=96=test/images/a.png'`. It is matched against the URL the `NetworkImage` requests, as `Uri` compares them.
* The file is relative to the working directory (or absolute), anywhere on disk. A file kept for one task goes under `.dart_tool/shutter/`; images every change is shot with can be committed, under `test/` for example.
* Repeatable, one per URL. A URL that is not served still fails, so a missed image is an `error` shot naming its URL, never a silent blank.
* The image is in the shot when an `Image` widget shows it (`Image.network`, or `Image(image: NetworkImage(...))`): `Image` widgets are precached before the capture.
* Only what `NetworkImage` fetches is served. Another HTTP client asking for a served URL, such as `package:http`, fails.

The run records each URL with its file and the file's sha256 in `manifest.json`; `shot` prints them, and `diff` prints both runs' when they differ, since another file changes the image without any widget changing.
They are not part of shot ids, so a run with `--network-image` pairs shot for shot with one without.

A preview can also pass the widget an image without HTTP, when the widget takes an `ImageProvider` rather than a URL: an `AssetImage`, or a `MemoryImage` of bytes the preview file holds.

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

### On-screen keyboard

`shot --keyboard <height>` lays every preview out as a device does while its on-screen keyboard is up: from the first frame, the view reports a bottom inset of that many logical pixels, which widgets read as `MediaQuery.viewInsets`.
A widget that reads the inset moves as on a device: a `Scaffold` shrinks its body to end above the keyboard (unless `resizeToAvoidBottomInset: false`), and so does a layout of the app's own that pads itself by `MediaQuery.viewInsetsOf`.
A widget that does not read it is shot as without `--keyboard`.
The inset leaves room above it only in a preview with a finite height, such as a screen.
The keyboard itself is not drawn: in either capture, the area it would cover shows what the app paints there, such as a `Scaffold`'s background, and the shot keeps the preview's full size.
`--keyboard-tint <color>` (`RRGGBB` or `AARRGGBB`, `#` optional: `9E9E9E`) paints that area in the color, over what the app paints there, and with `--capture screen` over menus and dialogs too. It only paints: actions reach the app under it as without it.
Keyboards differ in height by device and input method, so there is no default: give the height of the keyboard on the device the screen is laid out for. On that device, with the keyboard up, the app reads it as `MediaQuery.viewInsetsOf(context).bottom`, in the logical pixels `--keyboard` takes.
`--enter` puts text into a field without raising any keyboard, so the state while typing is shot with both:

```bash
shutter shot lib/preview/login_preview.dart --enter 'label:Email=example@example.com' --keyboard 336
```

When posting a shot without `--keyboard-tint`, say that the band at the bottom stands for the keyboard: nothing in the image shows it.
The run records the height and the tint as it does its actions; neither is part of shot ids, so a run with `--keyboard` pairs shot for shot with one without.

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

* One capture per preview, after the actions: scrolling and dragging are not shot. A sequence of states, such as the course of an animation, is shot as one run per point in time, each with its own `--settle`.
* No on-screen keyboard: text entered with `--enter` reaches the field, but the keyboard a device would show is not drawn, even with `--capture screen`, and the layout does not make room for it unless `--keyboard` is given (see Experimental); `--keyboard-tint` marks its area with a color.
* HTTP is blocked, so network images fail to load unless `--network-image` serves them.
* `flutter test` runs the engine with test fonts, which has no system font fallback. Shutter's host fonts reach paragraphs, text fields, the default text style, and the text themes of the shell and the preview's `theme`. Text a widget paints with its own `TextPainter`, such as a `Slider`'s value indicator, gets them only through those: under a `Theme` built in a `wrapper`, in the preview function, or in the widget itself, glyphs outside its fonts render as boxes, where a device would fall back to a system font. Give the app's theme through the shell or the preview's `theme` instead. Shutter does not see that text, so its characters add no host font.

## Engine

The engine is the only layer that knows how PNGs are made.
v1 (`flutter_test`) writes `.dart_tool/shutter/test/<run-id>/shutter_test.dart`, a harness, the design library adapters, and one helper library per source library (or one for `--widget`), runs `flutter test` on that path, and deletes the directory.
Each run has its own directory, so shots running at the same time do not overwrite each other's code.
The project gains no dependency; `flutter_test` in `dev_dependencies` is enough.
When Flutter ships a capture command in the previewer itself, it replaces v1 without changing runs or diffs.

## Runs

`.dart_tool/shutter/runs/<run-id>/` holds `<id>.png` per shot and `manifest.json` (`run`, `image` for a `semantics` run, `shell` when a shell file was used, `actions`, `capture`, `viewport`, `keyboard`, `keyboard_tint`, and `network_images` when given, `shots`).
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
With `--composite`, each entry that has something to show also gets `<id>-composite.png` there: the before, diff and after panels on the union canvas, each under its caption, as one image to attach on its own. The entry points at it as `composite`; both flags together write both files.
`--direction horizontal` puts the three panels side by side, `vertical` stacks them, and the default `auto` puts a portrait shot side by side and a landscape one stacked, so that all three panels stay in one view whatever the subject's shape.
An entry with an image on one side only — a shot the code no longer renders, or one whose id the edit changed — gets a sheet too, with the absent panel left as background and the diff panel all red. An entry whose two PNGs are identical gets none: there is nothing to draw.
The panels are never scaled, so a large subject makes a large PNG; the marked image of `--images` is the one to open when a change is too thin to survive a viewer scaling the sheet down.
A caption has its panel and the one gutter beside it: a caption too long for that is drawn a size down, and a diff caption too long even for the smallest font drops the share and keeps the pixel count, rather than running past the sheet's edge or over the next panel's.
`--title <text>` draws a line of text above the panels of every sheet. It is rendered by Flutter, so any script the host has a font for works; that needs a Flutter SDK, which the rest of `diff` does not.
Every sheet size is known before the title is drawn, so the text is laid out in exactly the room that size of sheet leaves between its gutters, at the size the caption bands are set in, and is neither scaled nor re-wrapped afterwards. That is one `flutter test` run per distinct sheet size: one for a diff of a single widget, more when the entries differ in size.
Because the text is laid out at the size it is drawn, the render says how many lines it took: a title that did not fit one line is reported on stderr with the width of the sheets it did not fit.
When the two runs were shot with different shells (path or sha256), `shell` shows each run's (`default` for the default shell): a shell change alters every image without any widget changing. The entries are compared as always.

## Output

`shot`, `semantics`, and `diff` print YAML starting with the comment `# shutter ai-report v1`, with absolute paths to open.
`shot` gives `run`, `shell` (the shell file with its sha256, or `default`), `actions`, `capture`, `viewport`, `keyboard`, `keyboard_tint`, and `network_images` (when given), `summary`, and `shots`, errors first.
`semantics` gives the same, with `image: semantics` after `shell`.
`diff` gives `diff` (with `--images` or `--composite`), `before`, `after`, `shell`, `image`, `actions`, `capture`, `viewport`, `keyboard`, `keyboard_tint`, and `network_images` (each when the two runs differ in it; `image` is `paint` for a `shot` run), `summary`, and `entries` in the order changed → added → removed → unchanged.

## Exit codes

| command     | 0               | 1              | 2                |
| ----------- | --------------- | -------------- | ---------------- |
| `shot`      | every shot ok   | —              | any shot `error` |
| `semantics` | every shot ok   | —              | any shot `error` |
| `diff`      | no difference   | differences    | —                |
| `doctor`    | no failed check | a failed check | —                |

Other failures follow sysexits: 64 usage, 66 missing run or file, 69 no Flutter SDK, 70 internal error, 78 project not usable.

## Commands

| command     | purpose                                                                                                                                                                                                                                                 |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `agent`     | the step-by-step playbook                                                                                                                                                                                                                               |
| `manual`    | this document                                                                                                                                                                                                                                           |
| `doctor`    | SDK version, font cache, shell (`--shell`)                                                                                                                                                                                                              |
| `init`      | write `shell.dart` (`--shell`)                                                                                                                                                                                                                          |
| `shot`      | render the named preview files, or one `--widget`, into a new run (`--widget`/`--import`/`--size`, `--settle`, `--shell`, `--tap`/`--enter`/`--press`/`--hover`/`--focus`, `--capture`/`--viewport`, `--keyboard`/`--keyboard-tint`, `--network-image`) |
| `semantics` | draw the semantics tree of the same subjects into a new run, with the options of `shot` except `--keyboard-tint`                                                                                                                                        |
| `diff`      | compare two runs (`--images`, `--composite`/`--direction`/`--title`)                                                                                                                                                                                    |
''';
