# Agent Guidelines

Conventions for AI coding agents (Claude Code, Cursor, Codex, etc.) and human contributors working on this repository. Operational rules first; rationale second. If a rule lives elsewhere (CHANGELOG, README, `doc/manual.md`, `doc/agent.md`), link rather than duplicate.

## Repository layout

* `bin/shutter.dart` — minimal CLI entrypoint; defers to `lib/src/entry_point.dart`.
* `lib/src/entry_point.dart` — `runApp` (guarded zone) and `runShutter` (exception → sysexits mapping). Tests drive `runShutter` with a `ShutterContext`.
* `lib/src/shutter_exception.dart` — expected failures with their sysexits code; `lib/src/version.dart` — `packageVersion`, generated from `pubspec.yaml` by `build_version` (`dart run build_runner build`); `lib/src/dart_literal.dart` — Dart string literals for generated code.
* `lib/src/cli/` — `CommandRunner` plus one file per subcommand. `context.dart` defines `ShutterContext`, which carries the working directory, clock, environment, and engine factory so commands run in tests without Flutter. `shot_options.dart` parses `shot`'s arguments. `agent_text.dart` and `manual_text.dart` are const mirrors of `doc/agent.md` and `doc/manual.md`; `test/cli/text_parity_test.dart` enforces byte equality.
* `lib/src/project/` — project root and pubspec fields, preview-dir convention, `.gitignore`, Flutter SDK lookup, and the `Process.run` seam the engine uses.
* `lib/src/scan/` — the previews of the preview files `shot` is given, with the analyzer's resolution: which annotations are previews, and each name they use rewritten through an import prefix. Tests resolve against a stub `package:flutter` (`test/helpers.dart`) and the Dart SDK running them.
* `lib/src/engine/` — the only swappable layer. `Engine` is the interface; `FlutterTestEngine` generates `.shutter/test/<run-id>/` (`generator.dart`, `design.dart`, `widget_shot.dart`) and runs `flutter test`. `harness_text.dart` is the Flutter-side runtime, shipped as a const string so target projects gain no dependency.
* `lib/src/fonts/` — the google_fonts file list the project resolves, and the download cache under `.shutter/fonts/google_fonts/`.
* `lib/src/run/` — run ids, `manifest.json` model, run lookup.
* `lib/src/diff/` — pixel comparison and classification. Pure Dart (`package:image`).
* `lib/src/reporters/` — the YAML output of `shot` and `diff`.
* `example/` — Flutter app with previews; the e2e tests copy it to a temp directory and shoot it.
* `skills/shutter-*/SKILL.md` — agent skills shipped with the package ([package skills](https://dart.dev/tools/pub/package-skills)). They say when to use shutter and defer to `shutter agent`; keep the playbook in `doc/agent.md`, not here. `test/skills_test.dart` checks names and frontmatter.
* `test/` mirrors `lib/src/`; `test/e2e/` is tagged `e2e` and needs a Flutter SDK.

## Workflow before every commit

Run, in this order, and address every finding:

```bash
dart format .
dart run dapper .
dart analyze
dart test
dart pub run coverage:test_with_coverage   # 100% line coverage required
dart test -P e2e                           # needs Flutter; drives example/
```

* `dart analyze` — strict lints are on; fix info-level findings too.
* 100% line coverage on `lib/` is a correctness signal: an uncovered line is read as dead code to delete, not a gap to paper over. The coverage run excludes `e2e`, so every line must be reachable from unit tests with fakes.
* The harness (`harness_text.dart`) is not measured by coverage; the e2e tests compile it, run it, and `flutter analyze` the generated files.

## Code style

* snake_case filenames in `lib/src/`; no leading-underscore filenames.
* Match the surrounding code's voice and comment density.
* Dart 3.13 features (primary constructors, records, patterns, dot shorthand, null-aware elements) are welcome where they read clearly. Target projects are Flutter 3.47+ (Dart 3.13+), so this holds for the harness and generated code too.
* Classes whose constructor only stores its parameters use a primary constructor, with each field's doc comment on its parameter.
* No tombstone comments when removing code; the "why" lives in the commit body.

## Documentation conventions

* README, AGENTS, CHANGELOG, and everything under `doc/` are English-only.
* One markdown bullet or sentence per source line. Don't soft-wrap mid-sentence.
* README is "back of the box". Operator detail goes to `doc/manual.md` (mirrored as `shutter manual`); the agent walkthrough goes to `doc/agent.md` (mirrored as `shutter agent`). After editing either, run `dart run dapper .` and copy the result into its `*_text.dart` mirror.
* Don't reference `tmp/` paths from tracked files.

## Changing the harness

`lib/src/engine/harness_text.dart` is Flutter code inside a raw string. It must not contain `'''`. After editing it, run `dart test -P e2e`: it renders `example/`, checks classifications, error locations, and PNG sizes, and runs `flutter analyze` on the generated files.

## Commits

* Conventional Commits 1.0.0 — `<type>[scope]: <description>`.
* One commit per logical unit; don't bundle reformatting with feature work.
* Sign commits when your git is configured for signing.
* Keep commit messages and PR bodies free of pre-merge hygiene stamps (test counts, coverage percentages).
* AI-authored commits carry a `Co-Authored-By: <model name> <noreply@anthropic.com>` footer naming the model the session actually runs.

## Release flow

1. Bump `version:` in `pubspec.yaml`, then run `dart run build_runner build` to regenerate `lib/src/version.dart`; `test/version_test.dart` fails when they drift.
2. Add a `## X.Y.Z` section to `CHANGELOG.md`.
3. Run `dart pub publish --dry-run` and check the archive contents against `.pubignore`.
4. The release commit is `chore(release): X.Y.Z` on a `release/vX.Y.Z` branch, merged via PR.

## Scratch space

`./tmp/` is gitignored. Put plans, intermediate artefacts, and debug scripts there. Nothing under `tmp/` may be referenced from tracked files.
