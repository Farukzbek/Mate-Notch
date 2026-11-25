#!/bin/bash
# Mate Notch derleme betiği.
#   ./build.sh            → hızlı geliştirme derlemesi: .build/dev/Mate Notch.app (bu Mac'in mimarisi)
#   ./build.sh --release  → evrensel (Apple Silicon + Intel) uygulama + DMG: dist/Mate Notch.app, dist/Mate-Notch.dmg
# Sürüm: VERSION=1.2.0 ./build.sh --release
set -e
cd "$(dirname "$0")"
# Sürüm: verilmezse son yayın etiketi (v1.0.1 → 1.0.1). Geliştirme derlemesi eski numara taşırsa uygulamanın kendi
# güncelleyicisi onu yayındaki sürümle değiştirirdi.
VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')}"
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
  <key>CFBundleDevelopmentRegion</key><string>tr</string>
  <key>CFBundleLocalizations</key><array><string>tr</string><string>en</string><string>de</string><string>es</string><string>fr</string><string>pt-BR</string></array>
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
  <key>NSBluetoothAlwaysUsageDescription</key><string>Bağlı Bluetooth cihazlarının (kulaklık, fare, klavye) pil seviyesini göstermek için.</string>
  <key>NSFocusStatusUsageDescription</key><string>Odak (Rahatsız Etmeyin) açıkken notch'ta küçük bir ay simgesi göstermek için.</string>
  <key>NSDownloadsFolderUsageDescription</key><string>İndirmelerin ilerlemesini göstermek için İndirilenler klasörüne bakar.</string>
  <key>NSCalendarsFullAccessUsageDescription</key><string>Sıradaki etkinliği göstermek için takvime erişim gerekli.</string>
  <key>NSCameraUsageDescription</key><string>Kamera aynası, yüzünü görebilmen için kameranı yalnızca sekme açıkken canlı gösterir. Görüntü kaydedilmez ve hiçbir yere gönderilmez.</string>
  <key>NSAudioCaptureUsageDescription</key><string>Ses mikseri, seçtiğin uygulamanın ses seviyesini ayarlamak için o uygulamanın sesini işler. Ses kaydedilmez ve hiçbir yere gönderilmez.</string>
</dict></plist>
EOT
# Yerelleştirme: Resources/Localizable.xcstrings (kaynak dil tr, çeviri en) → .lproj/*.strings; izin açıklamaları InfoPlist.strings
xcrun xcstringstool compile Resources/Localizable.xcstrings --output-directory "$APP/Contents/Resources"
mkdir -p "$APP/Contents/Resources/en.lproj"
cat > "$APP/Contents/Resources/en.lproj/InfoPlist.strings" <<'EOS'
"NSAppleEventsUsageDescription" = "Mate Notch needs this to control Apple Music and Spotify.";
"NSDesktopFolderUsageDescription" = "To save screenshots and recordings to your Desktop.";
"NSBluetoothAlwaysUsageDescription" = "To show the battery level of connected Bluetooth devices (headphones, mouse, keyboard).";
"NSFocusStatusUsageDescription" = "To show a small moon icon in the notch while Focus (Do Not Disturb) is on.";
"NSDownloadsFolderUsageDescription" = "Looks at the Downloads folder to show download progress.";
"NSCalendarsFullAccessUsageDescription" = "Calendar access is needed to show your next event.";
"NSCameraUsageDescription" = "The camera mirror shows your camera live, only while its tab is open, so you can see your face. Nothing is recorded or sent anywhere.";
"NSAudioCaptureUsageDescription" = "The audio mixer processes the audio of the app you pick to change its volume. Nothing is recorded or sent anywhere.";
EOS
mkdir -p "$APP/Contents/Resources/de.lproj" "$APP/Contents/Resources/es.lproj" "$APP/Contents/Resources/fr.lproj" "$APP/Contents/Resources/pt-BR.lproj"
cat > "$APP/Contents/Resources/de.lproj/InfoPlist.strings" <<'EOS'
"NSAppleEventsUsageDescription" = "Mate Notch benötigt dies, um Apple Music und Spotify zu steuern.";
"NSDesktopFolderUsageDescription" = "Um Bildschirmfotos und Aufnahmen auf deinem Schreibtisch zu sichern.";
"NSBluetoothAlwaysUsageDescription" = "Um den Akkustand verbundener Bluetooth-Geräte (Kopfhörer, Maus, Tastatur) anzuzeigen.";
"NSFocusStatusUsageDescription" = "Um ein kleines Mondsymbol im Notch zu zeigen, solange Fokus (Nicht stören) aktiv ist.";
"NSDownloadsFolderUsageDescription" = "Sieht in den Download-Ordner, um den Download-Fortschritt anzuzeigen.";
"NSCalendarsFullAccessUsageDescription" = "Der Kalenderzugriff wird benötigt, um deinen nächsten Termin anzuzeigen.";
"NSCameraUsageDescription" = "Der Kameraspiegel zeigt deine Kamera live, nur solange sein Tab geöffnet ist, damit du dein Gesicht sehen kannst. Nichts wird aufgezeichnet oder irgendwohin gesendet.";
"NSAudioCaptureUsageDescription" = "Der Audio-Mixer verarbeitet den Ton der gewählten App, um deren Lautstärke zu ändern. Nichts wird aufgezeichnet oder irgendwohin gesendet.";
EOS
cat > "$APP/Contents/Resources/es.lproj/InfoPlist.strings" <<'EOS'
"NSAppleEventsUsageDescription" = "Mate Notch lo necesita para controlar Apple Music y Spotify.";
"NSDesktopFolderUsageDescription" = "Para guardar capturas y grabaciones en tu Escritorio.";
"NSBluetoothAlwaysUsageDescription" = "Para mostrar el nivel de batería de los dispositivos Bluetooth conectados (auriculares, ratón, teclado).";
"NSFocusStatusUsageDescription" = "Para mostrar un pequeño icono de luna en el notch mientras el Enfoque (No molestar) esté activado.";
"NSDownloadsFolderUsageDescription" = "Consulta la carpeta Descargas para mostrar el progreso de las descargas.";
"NSCalendarsFullAccessUsageDescription" = "Se necesita acceso al calendario para mostrar tu próximo evento.";
"NSCameraUsageDescription" = "El espejo de cámara muestra tu cámara en directo, solo mientras su pestaña está abierta, para que puedas verte la cara. No se graba ni se envía nada.";
"NSAudioCaptureUsageDescription" = "El mezclador de audio procesa el sonido de la app que elijas para cambiar su volumen. No se graba ni se envía nada.";
EOS
cat > "$APP/Contents/Resources/fr.lproj/InfoPlist.strings" <<'EOS'
"NSAppleEventsUsageDescription" = "Mate Notch en a besoin pour contrôler Apple Music et Spotify.";
"NSDesktopFolderUsageDescription" = "Pour enregistrer les captures et enregistrements sur votre Bureau.";
"NSBluetoothAlwaysUsageDescription" = "Pour afficher le niveau de batterie des appareils Bluetooth connectés (casque, souris, clavier).";
"NSFocusStatusUsageDescription" = "Pour afficher une petite icône de lune dans le notch tant que la Concentration (Ne pas déranger) est activée.";
"NSDownloadsFolderUsageDescription" = "Consulte le dossier Téléchargements pour afficher la progression des téléchargements.";
"NSCalendarsFullAccessUsageDescription" = "L'accès au calendrier est nécessaire pour afficher votre prochain événement.";
"NSCameraUsageDescription" = "Le miroir caméra affiche votre caméra en direct, uniquement pendant que son onglet est ouvert, pour que vous puissiez voir votre visage. Rien n'est enregistré ni envoyé.";
"NSAudioCaptureUsageDescription" = "Le mixeur audio traite le son de l'app choisie pour changer son volume. Rien n'est enregistré ni envoyé.";
EOS
cat > "$APP/Contents/Resources/pt-BR.lproj/InfoPlist.strings" <<'EOS'
"NSAppleEventsUsageDescription" = "O Mate Notch precisa disto para controlar o Apple Music e o Spotify.";
"NSDesktopFolderUsageDescription" = "Para salvar capturas de tela e gravações na sua Mesa.";
"NSBluetoothAlwaysUsageDescription" = "Para mostrar o nível de bateria de dispositivos Bluetooth conectados (fones, mouse, teclado).";
"NSFocusStatusUsageDescription" = "Para mostrar um pequeno ícone de lua no notch enquanto o Foco (Não perturbe) estiver ativado.";
"NSDownloadsFolderUsageDescription" = "Olha a pasta Downloads para mostrar o progresso dos downloads.";
"NSCalendarsFullAccessUsageDescription" = "O acesso ao calendário é necessário para mostrar seu próximo evento.";
"NSCameraUsageDescription" = "O espelho da câmera mostra sua câmera ao vivo, apenas enquanto a aba está aberta, para você ver seu rosto. Nada é gravado nem enviado.";
"NSAudioCaptureUsageDescription" = "O mixer de áudio processa o som do app escolhido para mudar seu volume. Nada é gravado nem enviado.";
EOS
# İmza kimliği (sırayla): SIGN_ID ortam değişkeni → "Developer ID Application" → "Apple Development" → ad-hoc.
# KALICI bir kimlik şart: ad-hoc imzada macOS izinleri (Erişilebilirlik, Takvim…) derlemenin parmak iziyle (cdhash)
# eşler; her derlemede/güncellemede parmak izi değişince izinler geçersiz kalır. Sertifikayla imzalayınca izinler korunur.
IDS="$(security find-identity -v -p codesigning 2>/dev/null)"
if [ -z "${SIGN_ID:-}" ]; then
  AUTO_ID="$(echo "$IDS" | grep -m1 'Developer ID Application' | awk '{print $2}')"
  [ -z "$AUTO_ID" ] && AUTO_ID="$(echo "$IDS" | grep -m1 'Apple Development' | awk '{print $2}')"
fi
SIGN="${SIGN_ID:-${AUTO_ID:--}}"
IS_DEVID=0; [ "$SIGN" != "-" ] && echo "$IDS" | grep "$SIGN" | grep -q 'Developer ID Application' && IS_DEVID=1

# Sertleştirilmiş çalışma zamanı (hardened runtime) + gereken izinler (Resources/MateNotch.entitlements): Apple onayı (notarization)
# için şart; geliştirme derlemelerinde de açık tutulur ki bir özelliği bozarsa hemen anlaşılsın. HARDEN=0 ile kapatılır.
FLAGS=(--force --deep --sign "$SIGN")
if [ "${HARDEN:-1}" = 1 ] && [ "$SIGN" != "-" ]; then FLAGS+=(--options runtime --entitlements Resources/MateNotch.entitlements); fi
[ "$IS_DEVID" = 1 ] && FLAGS+=(--timestamp)        # Developer ID: güvenli zaman damgası (notarization için gerekli)
codesign "${FLAGS[@]}" "$APP"
if [ "$SIGN" = "-" ]; then echo "UYARI: ad-hoc imza; her derlemede izinler sıfırlanır"
elif [ "$IS_DEVID" = 1 ]; then echo "İmza: Developer ID ($SIGN)"
else echo "İmza: $SIGN (Developer ID değil: indirenler macOS uyarısı görür)"; fi
echo "Hazır: $(pwd)/$APP"

[ "$RELEASE" = 1 ] || exit 0

# ---- DMG ----
VENV=".build/dmgvenv"
if [ ! -x "$VENV/bin/dmgbuild" ]; then
  SIBLING="../mate-lyrics/.build/dmgvenv"            # Mate Lyrics'in hazır ortamı varsa onu kullan
  if [ -x "$SIBLING/bin/dmgbuild" ]; then VENV="$SIBLING"
  else python3 -m venv "$VENV" && "$VENV/bin/pip" install -q dmgbuild; fi
fi
# Apple onayı (notarization): Developer ID imzası + `xcrun notarytool store-credentials` ile saklanmış profil gerekir (docs/IMZA.md)
NOTARY_PROFILE="${NOTARY_PROFILE:-mate-studios-notary}"
NOTARIZE=""
if [ "$IS_DEVID" = 1 ] && xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then NOTARIZE=1; fi

BG=".build/dmg-bg"
# Onaysız sürümde DMG penceresinde "Yine de Aç" ipucu gösterilir
if [ -n "$NOTARIZE" ]; then BG_FLAG=""; else BG_FLAG="--gatekeeper-ipucu"; fi
swift tools/make-dmg-background.swift "$BG" $BG_FLAG
tiffutil -cathidpicheck "$BG/dmg-bg.png" "$BG/dmg-bg@2x.png" -out "$BG/dmg-bg.tiff" 2>/dev/null
rm -f dist/Mate-Notch.dmg
"$VENV/bin/dmgbuild" -s tools/dmg-settings.py -D app="$APP" -D bg="$BG/dmg-bg.tiff" "Mate Notch" dist/Mate-Notch.dmg >/dev/null
[ "$IS_DEVID" = 1 ] && codesign --force --timestamp --sign "$SIGN" dist/Mate-Notch.dmg
if [ -n "$NOTARIZE" ]; then
  echo "Apple onayına gönderiliyor (birkaç dakika sürebilir)…"
  xcrun notarytool submit dist/Mate-Notch.dmg --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple dist/Mate-Notch.dmg
  echo "Apple onayı: tamam"
else
  echo "Apple onayı: yok (indiren kişi ilk açılışta \"Yine de Aç\" demeli)"
fi
(cd dist && rm -f Mate-Notch.zip && ditto -c -k --keepParent "Mate Notch.app" Mate-Notch.zip)
shasum -a 256 dist/Mate-Notch.dmg | tee dist/Mate-Notch.dmg.sha256
echo "Hazır: dist/Mate-Notch.dmg  (+ Mate-Notch.zip)"
