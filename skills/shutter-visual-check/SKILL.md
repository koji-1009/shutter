---
name: shutter-visual-check
description: Render Flutter widgets to PNG and compare before / after with the shutter CLI. Use when a change affects how a Flutter widget or screen looks (layout, padding, text, colour, theme, new screen or state), to check the result by image instead of by "it compiles" or "tests pass".
---

# shutter: close a visual change with an image

* Run `shutter agent` before anything else and follow it. It is the playbook for this `shutter` binary; this skill only says when to use it.
* If `shutter` is not found, run `dart install shutter`. The Flutter project needs `flutter_test` in `dev_dependencies` and nothing else.
* Put the widget you are changing in a preview file (`lib/preview/<name>_preview.dart`: import the widget, return it from an `@Preview` function), then shoot before and after the edit and diff:

```bash
shutter shot lib/preview/<name>_preview.dart   # before; prints run: <dir>
# edit
shutter shot lib/preview/<name>_preview.dart   # after
shutter diff <before-run> <after-run>
```

* Open the PNG paths `diff` prints and check them against the intended change. Deciding whether the change is right is yours; shutter makes no judgement.
