<p align="center"><a href="README.tr.md">Türkçe</a> · <b>English</b> · <a href="README.de.md">Deutsch</a> · <a href="README.es.md">Español</a> · <a href="README.fr.md">Français</a> · <a href="README.pt-BR.md">Português (Brasil)</a></p>

<p align="center">
  <a href="https://github.com/Farukzbek/Mate-Notch/releases/latest"><img src="https://img.shields.io/github/v/release/Farukzbek/Mate-Notch?style=flat-square&color=8b7cff" alt="Latest release"></a>
  <a href="https://github.com/Farukzbek/Mate-Notch/releases"><img src="https://img.shields.io/github/downloads/Farukzbek/Mate-Notch/total?style=flat-square&color=5ab0ff" alt="Downloads"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black?style=flat-square&logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/notarized-by%20Apple-5be0a0?style=flat-square" alt="Notarized by Apple">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/Farukzbek/Mate-Notch?style=flat-square" alt="MIT license"></a>
  <a href="https://github.com/Farukzbek/Mate-Notch/stargazers"><img src="https://img.shields.io/github/stars/Farukzbek/Mate-Notch?style=flat-square&color=f5b301" alt="Stars"></a>
</p>

<p align="center">
  <img src="docs/icon.png" width="110" alt="Mate Notch icon">
</p>

<h1 align="center">Mate Notch</h1>

<p align="center">
  A lightweight macOS app that turns the MacBook notch into a control surface: music with synced lyrics, calendar, clipboard history, shelf, timer and more.
</p>

<p align="center">
  <a href="https://github.com/Farukzbek/Mate-Notch/releases/latest/download/Mate-Notch.dmg"><b>⬇️ Download for macOS (Mate-Notch.dmg)</b></a><br>
  <sub>macOS 14 or later · Apple Silicon and Intel · <a href="#installation">installation</a></sub>
</p>

<p align="center">
  <img src="docs/screenshot-open.png" width="720" alt="Mate Notch: open notch, Home">
</p>

## Features

- **Notch-aware:** Reads the physical notch size and opens with a springy animation on hover. On Macs without a notch it shows a virtual pill.
- **Music (Apple Music + Spotify):** Artwork, progress bar, play/pause/next/previous. The artwork colour tints the background.
- **Synced lyrics (Mate Lyrics engine):** Three lines on the music card (previous dim, current bright, next dim) and one or two lines under the closed notch. The area never opens for a song without lyrics. Uses [lrclib.net](https://lrclib.net).
- **Live activities (while closed):** music indicator, timer, charging, screen recording. The indicator icon is selectable (equalizer, sound wave, AirPods, HomePod, Apple logo…).
- **Shelf:** Drag a file onto the notch, then drag it back out wherever you need it. Right-click: Open, Quick Look, copy to clipboard, copy path, show in Finder, send with AirDrop.
- **Clipboard history:** A "Copied" banner on copy; search, pinning (persists across restarts), delete one or many, adjustable size and automatic expiry. Password-manager copies are never stored.
- **Colour picker:** Pick a colour from the screen and its hex code is copied to the clipboard.
- **Screenshot button:** Selected area, full screen, screen recording or the system capture tool.
- **AI:** Summarize, fix, rewrite, translate or explain clipboard or typed text; a daily summary from your calendar; free-form questions. Runs on the **on-device Apple model** by default (no key needed, data never leaves your Mac; requires Apple Intelligence). Optionally connect **Claude, ChatGPT or Gemini** with your own API key in Settings; keys are stored in the Keychain.
- **AirDrop:** Drag a file onto the AirDrop area in the Shelf tab to open the recipient picker.
- **Cache cleaner:** Lists unneeded cache and log files and what each belongs to; nothing is deleted without your confirmation.
- **Auto-update:** Checks GitHub Releases for new versions, verifies them (SHA-256 + signature) and updates itself (can be turned off in Settings).
- **Everyday use:** An Apple **Shortcuts** button, a **Join** button and a 5-minute alert for meetings with a link (Zoom, Meet, Teams…), **Pomodoro** (25/5, 15 every 4th break), an audio output picker, and automatic shelf clean-up after a chosen number of days.
- **Volume & brightness indicator:** A sleek indicator in the notch instead of macOS's square overlay (with Accessibility access the system overlay is hidden); style, size, colour, duration and key step are adjustable.
- **Focus and weather:** A moon icon while a Focus is on; the weather for your chosen city (°C/°F) on Home, with no location access.
- **Batteries and alerts:** Mac, headphone, mouse and keyboard batteries; a two-stage low-battery alert; a banner when headphones connect.
- **Permission wizard and feature tour:** On first launch you choose a language, grant permissions and try each feature one by one or skip; reopen it later from the menu. A **What's New** window appears after an update.
- **Mascot (optional):** A small buddy on the right wing of the closed notch: it reaches out when you copy, waves, bobs to the music, gets tired when the battery is low, puts on headphones, reacts when volume or brightness hits an extreme and to meetings, downloads and Focus, and sleeps when idle. Every behaviour can be turned off separately (Settings › Appearance & mascot).

<p align="center"><img src="docs/buddy.gif" width="440" alt="The mascot grabbing copied text"></p>

- **Languages:** Turkish, English, German, Spanish, French and Brazilian Portuguese (Settings › Behavior & tabs › Language, or the 🌐 button at the bottom of the sidebar).
- **Timer, system status (CPU / memory / disk), keep awake, next event from your calendar.**
- **Appearance:** Black, solid colour, album colour or **Liquid Glass** (adjustable density and glass type); open/closed size, hover area and delays are adjustable.
- **Back up settings:** Export and import from Settings › General.
- **Notes tab:** A one-line notepad in the notch. Click a note to copy it, or send it (or all of them) to the Notes app.
- **Audio mixer:** Set the volume of every app that is playing sound with vertical channels; click an icon to mute that app. Levels are remembered.
- **Camera mirror:** Use your camera as a mirror, take photos (saved to the Desktop, clipboard and shelf) and turn on a ring light with adjustable level, thickness and colour (white, yellow, blue). The camera only runs while the tab is open.
- **Shortcuts tab:** Pin Apple Shortcuts with your own icons and colours and run them with one click.
- **Interactive guide:** After setup a step-by-step guide spotlights each feature in the notch; restart it any time from the menu bar icon.
- **More music:** A sleep timer (stop after 15–90 min or when the song ends), a heart to like the song in Apple Music, and optional AI translation of the lyrics into your interface language.
- **Shelf tools:** Real preview thumbnails; click to select, press Space for the macOS Quick Look panel (← → to browse). Right-click an image to convert it (PNG, JPEG, HEIC, TIFF), shrink it or mark it up with arrows, boxes, a pen, a highlighter or a black redaction box.
- **World clock and network speed:** Up to three cities under the System tab with the time difference, plus live download/upload speed (Mbps or MB/s).
- Shortcut: `⌃⌥Space` toggles it, and you can assign your own global shortcut to every tab (Settings › Behavior & tabs › Shortcut). A smiling icon sits in the menu bar; it takes no space in the Dock.

## Installation

**With Homebrew:**

```bash
brew tap farukzbek/tap
brew install --cask mate-notch
```

**Or manually:**

1. Download [Mate-Notch.dmg](https://github.com/Farukzbek/Mate-Notch/releases/latest/download/Mate-Notch.dmg).
2. Open the DMG and drag **Mate Notch** to the **Applications** folder.
3. Open it from Applications and approve the permission prompts (Music/Spotify, Calendar).

The app is signed with a Developer ID and notarized by Apple, so no extra step is needed on first launch.

Settings: menu bar icon › **Settings…** (or the ⚙ in the open notch).

## Building from source

Requires Xcode 15+ (or Swift 5.9+ tools).

```bash
git clone https://github.com/Farukzbek/Mate-Notch.git
cd Mate-Notch
./build.sh              # quick build → "Mate Notch.app"
./build.sh --release    # universal app + DMG → dist/
```

## Publishing a release

```bash
./release.sh 1.0.0 "Release notes"
```

This builds, signs, notarizes, tags, pushes, creates the GitHub release with `Mate-Notch.dmg` and its checksum, and updates the Homebrew cask. The file must stay named `Mate-Notch.dmg`; the download link above points to it.

For signing and notarization see [docs/IMZA.md](docs/IMZA.md) (in Turkish).

## Support the project

If Mate Notch is useful to you, a ⭐ on GitHub helps other people find it, and sharing it with a friend helps even more. Bug reports and ideas are welcome in [Issues](https://github.com/Farukzbek/Mate-Notch/issues); see [CONTRIBUTING.md](CONTRIBUTING.md) to help with code or translations.

## License

MIT, see [LICENSE](LICENSE).
