#!/bin/bash
# Mate Notch derleme betiği.
#   ./build.sh            → hızlı geliştirme derlemesi: .build/dev/Mate Notch.app (bu Mac'in mimarisi)
#   ./build.sh --release  → evrensel (Apple Silicon + Intel) uygulama + DMG: dist/Mate Notch.app, dist/Mate-Notch.dmg
# Sürüm: VERSION=1.2.0 ./build.sh --release
set -e
cd "$(dirname "$0")"
VERSION="${VERSION:-1.0.0}"
RELEASE=0; [ "$1" = "--release" ] && RELEASE=1

if [ "$RELEASE" = 1 ]; then
  swift build -c release --arch arm64 --arch x86_64
  BIN=".build/apple/Products/Release/MateNotch"
  APP="dist/Mate Notch.app"
  mkdir -p dist
else
  swift build -c release
  BIN=".build/release/MateNotch"
  APP=".build/dev/Mate Notch.app"
  mkdir -p .build/dev
fi

# İkon yoksa üret
if [ ! -f Resources/AppIcon.icns ]; then
  swift tools/make-icon.swift Resources/AppIcon.iconset
  iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
fi

# Derleme çıktıları Spotlight/Launchpad aramasında "kopya uygulama" olarak çıkmasın
touch "$(dirname "$APP")/.metadata_never_index"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MateNotch"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<EOT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Mate Notch</string>
  <key>CFBundleDisplayName</key><string>Mate Notch</string>
  <key>CFBundleIdentifier</key><string>online.matestudios.matenotch</string>
  <key>CFBundleExecutable</key><string>MateNotch</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>© 2026 Mate Studios</string>
  <key>NSAppleEventsUsageDescription</key><string>Mate Notch, Apple Music ve Spotify'ı kontrol etmek için gerekli.</string>
  <key>NSDesktopFolderUsageDescription</key><string>Ekran görüntülerini ve kayıtları Masaüstü'ne kaydetmek için.</string>
  <key>NSCalendarsFullAccessUsageDescription</key><string>Sıradaki etkinliği göstermek için takvime erişim gerekli.</string>
</dict></plist>
EOT
# İmza: Developer ID varsa onunla (SIGN_ID="Developer ID Application: ..."), yoksa ad-hoc
codesign --force --deep --sign "${SIGN_ID:--}" "$APP"
echo "Hazır: $(pwd)/$APP"

[ "$RELEASE" = 1 ] || exit 0

# ---- DMG ----
VENV=".build/dmgvenv"
if [ ! -x "$VENV/bin/dmgbuild" ]; then
  SIBLING="../mate-lyrics/.build/dmgvenv"            # Mate Lyrics'in hazır ortamı varsa onu kullan
  if [ -x "$SIBLING/bin/dmgbuild" ]; then VENV="$SIBLING"
  else python3 -m venv "$VENV" && "$VENV/bin/pip" install -q dmgbuild; fi
fi
BG=".build/dmg-bg"
swift tools/make-dmg-background.swift "$BG"
tiffutil -cathidpicheck "$BG/dmg-bg.png" "$BG/dmg-bg@2x.png" -out "$BG/dmg-bg.tiff" 2>/dev/null
rm -f dist/Mate-Notch.dmg
"$VENV/bin/dmgbuild" -s tools/dmg-settings.py -D app="$APP" -D bg="$BG/dmg-bg.tiff" "Mate Notch" dist/Mate-Notch.dmg >/dev/null
[ -n "$SIGN_ID" ] && codesign --force --timestamp --sign "$SIGN_ID" dist/Mate-Notch.dmg
(cd dist && rm -f Mate-Notch.zip && ditto -c -k --keepParent "Mate Notch.app" Mate-Notch.zip)
shasum -a 256 dist/Mate-Notch.dmg | tee dist/Mate-Notch.dmg.sha256
echo "Hazır: dist/Mate-Notch.dmg  (+ Mate-Notch.zip)"
