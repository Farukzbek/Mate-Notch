# Contributing to Mate Notch / Katkıda bulunmak

Thanks for your interest! Mate Notch is a small SwiftUI/AppKit app (SwiftPM, macOS 14+). Everything is welcome: bug reports, ideas, translations, code.
Teşekkürler! Hata bildirimi, fikir, çeviri ve kod, hepsi çok değerli.

## Build / Derleme

```bash
git clone https://github.com/Farukzbek/Mate-Notch.git
cd Mate-Notch
./build.sh            # quick build → ".build/dev/Mate Notch.app"
```

Requires Xcode 15+. If you have no Developer ID certificate the build is ad-hoc signed; some permissions (Accessibility, Calendar…) are reset on every rebuild, which is expected.

## Good places to start / Başlamak için

- **Translations:** `Resources/Localizable.xcstrings` holds every string (source language is Turkish; `en`, `de`, `es`, `fr`, `pt-BR` are translated). Improve a wording or add a language, then run `./build.sh` and check it in *Settings › Behavior & tabs › Language*.
- **Settings search:** after adding a settings row run `python3 tools/gen_settings_index.py` so it shows up in the search.
- Issues labelled [`good first issue`](https://github.com/Farukzbek/Mate-Notch/labels/good%20first%20issue) are small and self-contained.

## Pull requests

- Keep a PR focused on one thing; describe what you tried and how you tested it.
- Match the surrounding code style. New user-facing text must go through `L("…")` / SwiftUI `Text("…")` so it can be translated.
- Never add network calls that send personal data; the app's promise is that data stays on the Mac unless the user connects a cloud AI provider.

## Reporting security problems

Please open a private security advisory on GitHub instead of a public issue.
