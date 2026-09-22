---
name: shutter-visual-check
description: Render Flutter widgets to PNG and compare before / after with the shutter CLI. Use when a change affects how a Flutter widget or screen looks (layout, padding, text, colour, theme, new screen or state, including a pressed, hovered, focused, or opened (menu, dialog) state), to check the result by image instead of by "it compiles" or "tests pass".
---

# shutter: close a visual change with an image

* Run `shutter agent` before anything else and follow it. It is the playbook for this `shutter` binary; this skill only says when to use it.
* If `shutter` is not found, run `dart install shutter`. The Flutter project needs `flutter_test` in `dev_dependencies` and nothing else.
* Name the preview files that already show the widget you are changing (any file under `lib/` with `@Preview` functions). For a widget without one, write a preview file in the preview dir (`lib/preview/`, or `lib/src/preview/` in a package: import the widget, return it from an `@Preview` function). Then shoot before and after the edit and diff:

```bash
shutter shot <preview-file>...   # before; prints run: <dir>
# edit
shutter shot <preview-file>...   # after
shutter diff latest~1 latest    # the last two runs
```

* For a state a gesture gives, add `--tap`, `--press`, `--hover`, or `--focus` to both shots, and `--capture screen` for what opens above the widget; `shutter agent` has the details.
* Open the PNG paths `diff` prints and check them against the intended change. Deciding whether the change is right is yours; shutter makes no judgement.
