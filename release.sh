#!/bin/bash
# Yeni sürümü yayınlar: derler, etiketler, GitHub Release oluşturur (gh CLI gerekli).
# Kullanım: ./release.sh 1.0.1 "Sürüm notları"
# Uygulamaların otomatik güncellemesi Releases'teki Mate-Notch.dmg + Mate-Notch.dmg.sha256 dosyalarına bakar.
set -e
cd "$(dirname "$0")"
V="$1"; NOTES="${2:-Mate Notch $V}"
[ -n "$V" ] || { echo "Kullanım: ./release.sh 1.0.1 \"notlar\""; exit 1; }
git diff --quiet && git diff --cached --quiet || { echo "Commit edilmemiş değişiklik var; önce commit'le."; exit 1; }
VERSION="$V" ./build.sh --release
git tag "v$V"
git push origin main "v$V"
gh release create "v$V" dist/Mate-Notch.dmg dist/Mate-Notch.dmg.sha256 --title "Mate Notch $V" --notes "$NOTES"
echo "Yayınlandı: v$V"

# Homebrew cask'ini yeni sürüme günceller (Farukzbek/homebrew-tap); başarısız olursa yayını bozmaz.
SHA="$(awk '{print $1}' dist/Mate-Notch.dmg.sha256)"
TAP="$(mktemp -d)"
if gh repo clone Farukzbek/homebrew-tap "$TAP" -- -q 2>/dev/null; then
  sed -i '' -E "s/^  version \".*\"/  version \"$V\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$TAP/Casks/mate-notch.rb"
  git -C "$TAP" -c user.name=TinyMateStudios -c user.email=TinyMateStudios@users.noreply.github.com commit -qam "mate-notch $V" \
    && git -C "$TAP" push -q && echo "Homebrew cask güncellendi: $V" || echo "Homebrew cask güncellenemedi (elle güncelle)"
fi
rm -rf "$TAP"
