# İmzalama ve Apple onayı (notarization)

Şu an sürümler "Apple Development" sertifikasıyla imzalanıyor: macOS izinleri (Erişilebilirlik, Takvim…) güncellemelerde korunuyor, ama indirenler ilk açılışta **"Yine de Aç"** uyarısını görüyor. **Developer ID** ile imzalayıp Apple'a onaylatınca (notarization) bu uyarı tamamen kalkar.

Betikler hazır: `build.sh` sertifikayı ve notarization profilini **kendiliğinden bulur**, bulamazsa bugünkü akışa döner. Sizin yapmanız gereken, bir kereye mahsus şu iki kurulum:

## 1. Developer ID Application sertifikası

Gerekenler: Apple Developer Program üyeliği ve hesapta **Account Holder** ya da **Admin** rolü.

1. **Anahtarlık Erişimi** › menü: *Anahtarlık Erişimi › Sertifika Yardımcısı › Sertifika Yetkilisinden Sertifika İste…* › e-postanı yaz, **Diske kaydedilen** seçeneğini işaretle › `.certSigningRequest` dosyasını kaydet.
2. <https://developer.apple.com/account/resources/certificates/add> › **Developer ID Application** › az önceki dosyayı yükle › `.cer` dosyasını indir › çift tıklayıp Anahtarlık'a ekle.
3. Kontrol:
   ```bash
   security find-identity -v -p codesigning | grep "Developer ID"
   ```
   Bir satır görüyorsan hazır.

## 2. Notarization profili

1. <https://account.apple.com> › *Oturum Açma ve Güvenlik › Uygulamaya Özel Parolalar* › yeni parola oluştur.
2. Takım Kimliğini (Team ID) <https://developer.apple.com/account> › *Üyelik Ayrıntıları*'ndan al.
3. Parolayı Anahtarlık'a kaydet (parola komuta yazılır, depoya girmez):
   ```bash
   xcrun notarytool store-credentials "mate-studios-notary" \
     --apple-id "APPLE_KIMLIGIN" --team-id "TAKIM_KIMLIGI" --password "uygulamaya-ozel-parola"
   ```
   Başka bir ad kullanırsan: `NOTARY_PROFILE=ad ./release.sh …`

## Yayınlama

```bash
./release.sh 1.1.0 "Sürüm notları"
```

Sertifika ve profil varsa betik: Developer ID ile imzalar → sertleştirilmiş çalışma zamanı (hardened runtime) → DMG'yi Apple'a gönderir → onayı bekler → DMG'ye mühür (staple) basar → DMG arka planındaki "Yine de Aç" ipucunu kaldırır. Çıktıda `Apple onayı: tamam` yazar.

## Bilinmesi gerekenler

- **İzinler bir kez sıfırlanır:** İmza kimliği Apple Development'tan Developer ID'ye geçince macOS bunu farklı bir uygulama sayar; kullanıcılar Erişilebilirlik ve Takvim gibi izinleri yeniden verir (izin sihirbazı bunu kolaylaştırır). Sonraki sürümlerde izinler korunur.
- **Otomatik güncelleme** yeni kimliğe sorunsuz geçer (indirilen paketin imzası ve sağlama toplamı doğrulanır).
- **Kendi kendini sınama:** `"/Applications/Mate Notch.app/Contents/MacOS/MateNotch" --selftest rapor.txt` ses, parlaklık, pil, Bluetooth, takvim, müzik ve ağı dener, sonucu dosyaya yazar (imza/izin sorunlarını bulmak için).
