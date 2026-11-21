#!/usr/bin/env python3
"""Ayarlar satır dizinini üretir ve Views.swift'teki satırlara .srow("anahtar") ekler.

Kullanım (proje kökünde):  python3 tools/gen_settings_index.py
- Views.swift içindeki `sectionView` fonksiyonunda Toggle / Picker / Slider'lı HStack satırlarını bulur,
  satırın sonuna `.srow("bölüm/başlık")` ekler (zaten ekliyse dokunmaz),
- Resources/Localizable.xcstrings'ten başlığın tüm dillerdeki karşılıklarını okuyup
  Sources/MateNotch/SettingsIndex.swift dosyasına yazar (arama dilden bağımsız çalışsın diye).
Yeni bir ayar satırı eklediğinde betiği yeniden çalıştır.
"""
import json, re, sys

VIEWS = "Sources/MateNotch/Views.swift"
CATALOG = "Resources/Localizable.xcstrings"
OUT = "Sources/MateNotch/SettingsIndex.swift"

# Elle eklenen eş anlamlılar (başlık → ek arama sözcükleri)
EXTRA = {
    "Dil": "language sprache idioma langue lingua língua taal",
    "Girişte otomatik başlat": "login startup launch at login autostart",
    "Gösterge stili": "hud indicator style bar percent",
    "Tuş başına değişim": "step key press volume brightness",
}

def strip_strings(s):
    return re.sub(r'"(?:\\.|[^"\\])*"', '""', s)

def depth(line):
    t = strip_strings(line)
    t = t.split("//")[0]
    return sum(t.count(c) for c in "([{") - sum(t.count(c) for c in ")]}")

src = open(VIEWS).read().split("\n")
start = next(i for i, l in enumerate(src) if "func sectionView(_ id: String)" in l)
end = next(i for i in range(start, len(src)) if src[i].strip() == "default: EmptyView()")

cat = json.load(open(CATALOG))["strings"]
def translations(title):
    e = cat.get(title)
    out = [title]
    if e:
        for lang in ("en", "de", "es", "fr", "pt-BR"):
            v = e.get("localizations", {}).get(lang, {}).get("stringUnit", {}).get("value")
            if v: out.append(v)
    return " ".join(out)

rows = []
seen = {}
section = None
i = start
while i < end:
    line = src[i]
    m = re.match(r'^        case "([a-z]+)":\s*$', line)
    if m: section = m.group(1); i += 1; continue
    s = line.strip()
    kind = None; title = None
    mm = re.match(r'^(Toggle|Picker)\("((?:\\.|[^"\\])*)"', s)
    if mm: kind, title = mm.group(1), mm.group(2)
    elif s.startswith("HStack {"):
        # Slider'lı satır mı? ilk Text başlığını al
        j, d = i, 0
        block = []
        while True:
            block.append(src[j]); d += depth(src[j]); j += 1
            if d <= 0 or j >= end: break
        joined = "\n".join(block)
        tm = re.search(r'Text\("((?:\\.|[^"\\])*)"\)', joined)
        if "Slider(" in joined and tm: kind, title = "HStack", tm.group(1)
    if not (section and kind and title) or ".srow(" in line and kind != "HStack":
        i += 1; continue
    # ifadenin bittiği satırı bul
    j, d = i, 0
    while True:
        d += depth(src[j])
        if d <= 0: break
        j += 1
        if j >= end: sys.exit(f"çözülemedi: {line}")
    if ".srow(" in src[j]:
        # zaten eklenmiş: dizine yine de gir
        key = re.search(r'\.srow\("([^"]+)"\)', src[j]).group(1)
    else:
        n = seen.get((section, title), 0); seen[(section, title)] = n + 1
        key = f"{section}/{title}" + (f"#{n}" if n else "")
        if "//" in strip_strings(src[j]): sys.exit(f"satır sonunda yorum var: {src[j]}")
        src[j] = src[j].rstrip() + f'.srow("{key}")'
    rows.append((key, section, title))
    i = j + 1

open(VIEWS, "w").write("\n".join(src))

def esc(s): return s.replace("\\", "\\\\").replace('"', '\\"')
lines = ["// Otomatik üretildi: tools/gen_settings_index.py — elle düzenleme.", "import Foundation", "",
         "struct SettingRowItem { let key: String; let section: String; let title: String; let search: String }", "",
         "enum SettingsIndex {", "    static let rows: [SettingRowItem] = ["]
for key, section, title in rows:
    words = translations(title) + " " + EXTRA.get(title, "")
    lines.append(f'        SettingRowItem(key: "{esc(key)}", section: "{section}", title: "{esc(title)}", search: "{esc(words)}"),')
lines += ["    ]", "}", ""]
open(OUT, "w").write("\n".join(lines))
print(f"{len(rows)} satır dizinlendi")
