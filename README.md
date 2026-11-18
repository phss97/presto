# Presto

Presto translates the text you highlight, in any app, with a keyboard shortcut. Translation runs on your Mac: it uses Apple Intelligence when available and falls back to a local model through llama.cpp. No text leaves your machine.

| Shortcut | Action |
| --- | --- |
| `⌃⌥T` | Translate the selection to your default language and replace it |
| `⌃⌥⇧T` | Pick a language, then translate the selection |

You can change both shortcuts in settings.

## Requirements

- macOS 26 or later
- Apple's Command Line Tools with Swift 6.2 or later (`xcode-select --install`)
- For the Apple Intelligence engine, a Mac with Apple Intelligence turned on. Otherwise pick a local model in settings, which you download once.

## Translation model

Settings → Translation Model lists one row per engine, each with its own action:

| Option | Notes |
| --- | --- |
| HY-MT1.5 1.8B (Recommended) | Tencent model tuned for translation, ~1.1 GB. Default for new installs |
| Apple Intelligence | No download. Some text may be refused by Apple's on-device model |
| Qwen 2.5 1.5B | General-purpose model, ~986 MB |
| TranslateGemma 4B | Google model tuned for translation, ~2.5 GB |
| Custom GGUF | Any GGUF file on your Mac, chosen with the file picker |

Click **Download** on a local model and Presto stores it in `~/Library/Application Support/Presto/Models`. Switching back to a model you already downloaded is instant.

**Fallback** picks a second model for when the selected one isn't ready — for example while a new model is downloading, or when Apple Intelligence is unavailable. Presto never starts a download on its own, so an unconfigured model shows a reminder instead of a progress bar.

## Install

```bash
git clone https://github.com/phss97/presto.git
cd presto
./scripts/build-app.sh --install
```

The script downloads llama.cpp, builds the app and installs it to `/Applications/Presto.app`. Then open Presto from Applications or Spotlight.

On first launch:

1. Grant **Accessibility** access when asked (System Settings → Privacy & Security → Accessibility). Presto needs it to read and replace the highlighted text.
2. Choose your default language and check the shortcuts.
3. Close the window. Presto keeps running in the background and starts at login. Open the app again whenever you want to change settings.

## Keep Accessibility access across rebuilds

By default the build is signed ad hoc, so macOS treats every rebuild as a new app and you must grant Accessibility again. To avoid that, create a local signing certificate once:

1. Open Keychain Access → Certificate Assistant → Create a Certificate.
2. Name it `Presto Local Signing`, choose **Self Signed Root** and **Code Signing**, then click Create.

The build script uses it automatically. To use a certificate with another name, set `PRESTO_SIGN_IDENTITY`. When macOS asks to use the key in your login keychain, enter your Mac login password and click **Always Allow**.

## Build options

| Option | Effect |
| --- | --- |
| `--install [dir]` | Install the app to `/Applications`, or to `dir` |
| `--bundle-model [file.gguf]` | Ship a local model inside the app (HY-MT1.5 1.8B by default) |

## License

MIT. See [LICENSE](LICENSE).
