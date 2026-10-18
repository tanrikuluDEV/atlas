# Atlas — coğrafya bulmacası

Bağımsız bir coğrafya bulmacası (kendi özellikleri olan ayrı bir uygulama; hiçbir yerde başka bir oyunun "Türkçe sürümü" diye tanıtılmaz, kullanıcı istedi). Gizli bir il ya da ülke seçilir; her tahmin, gizli yere olan en yakın sınır mesafesine göre haritada sıcak–soğuk renklerle boyanır. Dört sürüm var ve hepsi aynı oyunu oynatır:

| Sürüm | Konum | Durum |
|---|---|---|
| macOS uygulaması | `Atlas/` (SwiftUI, macOS 14+) | Çalışıyor; `build/` içinden açılıyor |
| iPhone uygulaması | `Atlas/` (aynı kod, iOS 17+) | Geliştirici imzasıyla iki telefona yüklü: iPhone 11 Pro Max ("Azi") ve iPhone 17 Pro Max ("iPhone") |
| Apple TV uygulaması | `Atlas/` (aynı kod, tvOS 17+; TV'ye özel arayüz `TVViews.swift`) | Kullanıcının Apple TV 4K'sına ("Oturma Odası") geliştirici imzasıyla yüklü |
| Web uygulaması | `web/` (saf JS, derleme yok) | Yayında: https://atlas-bulmaca.vercel.app (arkadaşlarla paylaşılıyor) |

Kullanıcıyla Türkçe konuşulur; arayüz metinleri ve kod yorumları da Türkçedir.

## Klasör yapısı

- `Atlas/Models/Place.swift`: `Place`, `GameCategory` (8 kategori), `PlaceSet` (kategori başına yerler, mesafeler, harita görünümü, arama), `WorldData`.
- `Atlas/Game/GameModel.swift`: oyun durumu, `DailyPuzzle` (günlük seçim, SplitMix64 + Swift `shuffled`).
- `Atlas/Game/Stats.swift`: kategori ve mod başına istatistik, oyun geçmişi (`GameRecord`, ipucu sayısıyla).
- `Atlas/Game/Progression.swift`: puan (XP) ve seviye formülleri, `LevelProgress`, `Reward`. Web karşılığı `web/js/progression.js` (formüller birebir aynı olmalı).
- `Atlas/Views/Brand.swift`: marka renkleri, `AtlasMark` (pin içinde küre), `LevelPin`, `SplashView` (açılış), `LevelCard` (seviye kartı ve puan animasyonu). Web karşılığı `web/js/brand.js` + `style.css`'teki marka bölümü. Logo yazı tipi `Atlas/Resources/BricolageGrotesque-ExtraBold.ttf` / `web/fonts/bricolage-800.woff2` (yalnızca "Atlas" harfleri ve rakamlar gömülü; başka metinde kullanma).
- `Atlas/Views/`: `ContentView` (panel, tahmin girişi, konfeti katmanı), `MapView` (kamera + `MapLayer` çizimi: düz harita ya da Dünya için küre, adlar, parlama animasyonları, `LegendView`), `MapGeometry` (düz projeksiyon `MapGeometry`, küre `GlobeGeometry` + `GlobeProjection`), `Sheets` (sonuç, istatistik, yardım), `StatsExtras` (`CalendarSection`, `DiscoverySection`), `ProgressSection` (gelişim grafiği), `ConfettiView`, `SettingsView`, `Platform` (macOS/iOS farkları), `DebugSnapshots`.
- `Atlas/Resources/`: `provinces.json` (81 il + mesafe matrisi), `world.json` (200 ülke, 5 dilde adları (`names`), arka plan bölgeleri, mesafe matrisi), `strings.json` (arayüz metinleri, 6 dil; web'le ortak), `hints.json` (her il ve ülke için 6 dilde 3 ipucu; `tools/hints/*.json`'dan üretilir).
- `Atlas/Views/TVViews.swift` (yalnızca tvOS): `TVHeader` (üst çubuk), `TVGuessInput` (dikteye dayanıklı tahmin girişi), `PlaceSet.voiceMatch` (tanımlık atma, ön ek ve harf farkıyla eşleştirme). `Platform.isTV` / `Platform.drawScale` (TV'de harita etiketleri 2 kat).
- `Atlas/Voice/` (iPhone + Apple TV): `VoiceLink.swift` — `VoiceHost` (TV: Bonjour `_atlas-voice._tcp` ile duyurur, gelen adları `TVGuessInput`'a iletir), `VoiceRemote` (iPhone: TV'yi bulup TCP ile bağlanır, Speech ile dinler, metni gönderir; mesajlar satır satır JSON). `VoiceRemoteView.swift` — iPhone'da "TV'ye söyle" sayfası. İzin metinleri ve Bonjour türü `Config/Voice-Info.plist`'te (iOS ve tvOS hedeflerinin `INFOPLIST_FILE`'ı; geri kalan anahtarlar üretilir).
- `Atlas/Models/Hints.swift`: ipuçlarını yükler (iller plaka koduyla, ülkeler ISO koduyla). Web karşılığı `hintsFor()` (`web/js/places.js`).
- `Atlas/Models/Localization.swift`: `AppLanguage`, `L10n` (seçili dil), `L("anahtar", ["n": 3])` çeviri işlevi. Web karşılığı `web/js/i18n.js` (`t()`), bölge tespiti için `web/api/geo.js` (Vercel'in `x-vercel-ip-country` başlığını döndürür).
- `web/js/`: `daily.js` (Swift'le birebir aynı günlük seçim, BigInt), `places.js`, `game.js`, `map.js` (düz harita + küre, adlar, lejant, parlama, keşif haritası), `colors.js`, `confetti.js`, `app.js` (arayüz, istatistik penceresi: takvim, keşif, gelişim). `web/data/` = `Atlas/Resources/` kopyası.
- `tools/cdp.mjs`: web sürümünü headless Chrome'da süren test aracı (adımları JSON olarak alır, ekran görüntüsü ve konsol hatalarını verir).
- `tools/`: veri üretimi (aşağıda). `project.yml`: xcodegen tanımı.

## Komutlar

```sh
# Xcode projesini üret (project.yml değişince ya da yeni dosya eklenince)
xcodegen generate

# macOS: derle ve aç
xcodebuild -project Atlas.xcodeproj -scheme Atlas -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/Atlas.app

# iPhone: derle ve yükle (telefon bağlı olmalı)
xcodebuild -project Atlas.xcodeproj -scheme AtlasiOS -configuration Debug \
  -destination 'id=00008030-001244320E12802E' -derivedDataPath build -allowProvisioningUpdates build
xcrun devicectl device install app --device 35B5DCFD-6DA2-52FD-A4EF-EBF4D3E399CB build/Build/Products/Debug-iphoneos/Atlas.app
# İkinci telefon (iPhone 17 Pro Max, "iPhone", ağ üzerinden): derleme id=00008150-00124D982284401C, kurulum --device A6313783-B8DE-5D58-B9B7-DBB14CCA1715

# Apple TV ("Oturma Odası", ağ üzerinden): derle ve yükle
xcodebuild -project Atlas.xcodeproj -scheme AtlasTV -configuration Debug \
  -destination 'id=00008110-0006299802C2801E' -derivedDataPath build -allowProvisioningUpdates build
xcrun devicectl device install app --device FF1FE4C7-5887-5E04-8996-722B9CEAC31B build/Build/Products/Debug-appletvos/Atlas.app
# Apple TV simülatörü ("Atlas TV" kurulu)
xcodebuild -project Atlas.xcodeproj -scheme AtlasTV -configuration Debug -destination 'generic/platform=tvOS Simulator' -derivedDataPath build build
xcrun simctl install "Atlas TV" build/Build/Products/Debug-appletvsimulator/Atlas.app && xcrun simctl launch "Atlas TV" com.atanrikulu.atlas.tv

# Web: yerelde dene, yayınla
cd web && python3 -m http.server 8765
cd web && npx vercel deploy --prod --yes

# Veriyi yeniden üret (sonra web/data/ altına kopyala)
python3 tools/build_data.py                      # iller → Atlas/Resources/provinces.json
python3 tools/build_world.py                     # ülkeler → Atlas/Resources/world.json (mesafesiz)
python3 tools/country_names.py                   # yalnızca 5 dildeki ülke adlarını world.json'a ekler/günceller
python3 tools/build_hints.py                     # tools/hints/*.json → hints.json (eksik dil ve ipucunda yer adı geçmesini denetler)
swiftc -O tools/compute_distances.swift -o /tmp/cd && /tmp/cd   # world.json'a mesafe matrisini ekler
swift tools/make_icons.swift                     # tüm ikonlar: iOS (açık+koyu), macOS, Apple TV (katmanlı + üst raf), web (PWA, favicon, og.png)
cp Atlas/Resources/*.json web/data/   # strings.json dahil; metin değişince de kopyala

# Haritaları, odak kadrajlarını ve istatistik bölümlerini ekran dışında PNG olarak çiz (yalnızca Debug)
build/Build/Products/Debug/Atlas.app/Contents/MacOS/Atlas -renderSnapshots <klasör>

# Web'i headless Chrome'da test et (yerel sunucu açıkken)
node tools/cdp.mjs http://127.0.0.1:8765/ 1280 800 1 adimlar.json <klasör>
```

## Uyulması gereken kurallar

- **Her güncelleme GitHub'a da gider.** Depo: https://github.com/tanrikuluDEV/atlas (gizli/private, dal `main`). Bir iş bitince değişiklikler Türkçe bir mesajla commit edilip `git push` yapılır (kullanıcı bunu kalıcı olarak istedi). `gh`'de etkin hesap `azerozgurr` adıyla kayıtlı ama GitHub adı `tanrikuluDEV`; `halisahamobile` (azertanrikulu) hesabına geçme. `.gitignore` `build/`, `.env*` ve `.vercel/`'ı dışarıda tutar; `web/.env.local` asla commit edilmez. Commit mesajlarına `Co-Authored-By: Claude …` satırı **eklenmez** (GitHub'da Claude katkıda bulunan olarak görünüyordu; kullanıcı istemedi).
- **Günlük bulmaca üç sürümde aynı olmalı.** `web/js/daily.js` Swift'teki `DailyPuzzle` ile birebir aynı sonucu verir (64 test durumuyla doğrulandı). Kategori sırası (`GameCategory.allCases` ↔ `CATEGORIES`), tohum, epoch (1 Ocak 2026) ya da yer sırası değişirse herkesin günlük bulmacası bozulur. Oyun mantığındaki değişiklikler genelde hem Swift'e hem `web/`'e uygulanmalı.
- **Türkiye için eski anahtarlar korunur:** istatistik anahtarı `stats` / `stats.practice`, günlük kayıt anahtarı `daily.<gün>` (kullanıcının mevcut istatistikleri bunlarda).
- **Web her yayında:** `web/js/version.js` içindeki `VERSION` ve `web/sw.js` içindeki `CACHE` (`atlas-vN`) birlikte artırılır. Veri dosyaları `?v=VERSION` ile istenir (eskiden `data/` 24 saat önbellekleniyordu ve dönen kullanıcılar eski `world.json` yüzünden ülke adlarını Türkçe görüyordu). Sayfa, yeni service worker devreye girince kendini yeniler; Ayarlar'da sürüm görünür. Şu an: Sürüm 11. `npx vercel deploy` ilk denemede ara sıra `"status": "error"` veriyor; tekrar denemek yetiyor (canlı `VERSION`'ı curl ile doğrula).
- **Gizli bilgi:** Vercel CLI `web/.env.local` dosyasına bir OIDC anahtarı yazar. `web/.vercelignore` bunu (`.env*`) hariç tutar; silinmemeli.
- **Sistem süreçlerine dokunma:** Dock'u `killall Dock` ile yeniden başlatmak bir kez Dock'un geri gelmemesine ve masaüstünün kararmasına yol açtı; ardından Terminal'in Masaüstü erişimi de kayboldu. Dock, Finder gibi sistem süreçleri kullanıcıya sorulmadan yeniden başlatılmaz.
- **Ekran görüntüsü:** Terminal'in ekran kaydı izni yok. Mac uygulaması için `-renderSnapshots`, iPhone için simülatör (`xcrun simctl io … screenshot`), web için headless Chrome'u DevTools protokolüyle süren bir Node betiği kullanıldı.

## Verilen kararlar

**Oyun**
- Kategoriler: Türkiye (81 il), Avrupa (48), Asya (51), Afrika (55), Kuzey Amerika (24, Orta Amerika ve Karayipler dahil), Güney Amerika (12), Okyanusya (14), Dünya (200).
- Mesafe = iki yerin en yakın sınırları arası (köşe–kenar). Komşular 0 km (iller için < 2 km, ülkeler için < 5 km).
- Her kategorinin kendi günlük bulmacası ve istatistikleri var; istatistikler Günlük ve Alıştırma olarak ayrı tutulur. Alıştırmada bitirilen her oyun sayılır; bitirilmeden bırakılan oyun sayılmaz.
- Ayarlar'daki km anahtarı kapalıyken yalnızca kilometre gizlenir, "Komşu" bilgisi görünmeye devam eder.
- Oyun bitince Enter yeni oyunu (alıştırma) başlatır; sonuç penceresinde "Yeni oyun" ilk ve seçili düğmedir.
- Tahmin listesinden bir satıra tıklayınca o yer mor çerçeve ve etiketle vurgulanır, kamera oraya gider. Bu oyun sırasında da çalışır.

**Harita ve kamera**
- Her tahminde kamera yere ve çevresine yumuşakça uçar. Görünen alan, yerin ana toprağının (uzak adalar hariç) ~5,2 katıdır ve kategoriye göre sınırlanır: Türkiye 0,4–0,55; kıtalar 1/3–0,5; Dünya 0,14–0,18 (harita genişliğine oranla). Kullanıcı önce "2 kat uzak" istedi; Dünya ölçeğini ise İzlanda ekran görüntüsüne göre ayarladı.
- Uzak bir yere geçerken kamera önce hafifçe uzaklaşır, sonra yaklaşır. Pes edince gizli yere uçar (web).
- Ekranda 6 noktadan küçük kalan yerler (Vatikan, Malta, ada ülkeleri) nokta olarak işaretlenir.
- **Dünya kategorisi 3D küre** (ortografik izdüşüm; arka yüzdeki noktalar ufuk çemberine yaslanır). Açılışta Türkiye tarafı (32°D, 28°K) görünür. Sürükleme döndürür. Odakta görünen açı 48–62°. Uzak yere geçerken önce uzaklaşıp döner.
- Tahmin edilen yerlerin adı haritada **mutlaka** yazar (oyun bitince gizli yerin de; kullanıcı istedi). Ad sığmıyor ya da çakışıyorsa yakındaki boş bir yere (gerekirse komşunun üstüne) kayar ve ince çizgi + noktayla yerine bağlanır; ekran kenarında içeri itilir. Hiç boş yer yoksa en az çakışan konum seçilir. Yerleşim sırası: önce gizli yer, sonra en yakın tahmin. Swift `LabelLayout` (MapView.swift) ↔ web `placeLabel` (map.js), aday sırası aynı.
- Köşede renk skalası (lejant): komşu · maks. mesafenin ¼'ü · maks. (km kapalıysa "yakın / uzak").
- Animasyonlar: yeni tahminde 1,3 sn beyaz parlama; bulununca 2,6 sn yeşil nabız ve konfeti (azaltılmış hareket ayarında konfeti yok).

**Veri (siyasi tercihler)**
- Kaynak: Natural Earth 1:50m (ülkeler), cihadturhan/tr-geojson (iller).
- Oyunda olanlar: BM üyeleri, Vatikan, Filistin, Kosova, Tayvan, Batı Sahra, Grönland, KKTC (ayrı ülke). Güney Kıbrıs "Güney Kıbrıs" adıyla.
- Somaliland, Somali'ye birleştirildi. Bağımlı bölgeler (Porto Riko, Jersey…) yalnızca arka planda çiziliyor.
- Türkiye, Rusya, Kıbrıs ve KKTC hem Avrupa hem Asya kategorisinde.
- Fransa, Fransız Guyanası üzerinden Brezilya ve Surinam ile komşu sayılır.

**Diller**
- Arayüz 6 dilde: Türkçe, İngilizce, Almanca, Fransızca, İspanyolca, İtalyanca. Elle seçilmemişse dil bölgeye göre seçilir: web'de bağlanılan ülke (IP, `/api/geo`), Mac/iPhone'da cihazın bölge ayarı; eşleşmezse cihaz/tarayıcı dili, o da yoksa İngilizce.
- Dil seçici ana ekranda üstte (bayrak): web'de araç çubuğu, iPhone'da ••• menüsünün yanı, Mac'te araç çubuğu + "Dil" menüsü. Seçim kalıcıdır (`language` / `atlas.language`).
- Ülke adları her dilde aranabilir (Almanya'yı "Germany" ya da "Allemagne" yazarak da bulursun); öneriler seçili dilde. İl adları her dilde aynı. Kayıtlar ve sıralama Türkçe adla (`trName`), günlük bulmaca etkilenmez.
- Kıbrıs adları Türkçedeki tercihle aynı: "South Cyprus / Südzypern…" ve "Northern Cyprus…". Türkiye İngilizcede "Türkiye".
- Telefonda sığması için mod adları kısa: İtalyanca "Oggi / Libera", Fransızca "Du jour / Libre".

**İpuçları**
- Her turda 3 ipucu: ilki en genel, sonuncusu en belirgin (çoğu ülkede başkent). Panelde "İpucu al" düğmesiyle tek tek açılır; oyun bitince üçü de "Bu yer hakkında" başlığıyla görünür.
- Açılan ipucu sayısı günlük kayıtta (`hints`) saklanır ve paylaşım metnine "💡 n ipucu" olarak eklenir; istatistikleri etkilemez.
- Almancada tahmin "Tipp" olduğu için ipucu "Hinweis".

**Apple TV**
- Düzen: harita ekranın solunu köşeden köşeye kaplar (sol, üst ve alt güvenli alan yok sayılır; lejant ve +/− düğmeleri güvenli alanın içinde). Sağda 480 pt'lik sütun: iki satırlık başlık (başlık + küçük bayrak + •••; kategori ve mod menüleri), altında panel. Bayrak ve ••• `fixedSize` (dar sütunda bayrak kırpılıyordu). Kullanıcı haritayı "sol üst ve sol alt köşelere kadar" ve paneli dar istedi. Her şey kumandayla odaklanır.
- Kumandanın mikrofon (Siri) düğmesi sisteme ayrılmış; uygulama onu da kumanda mikrofonunu da kullanamaz (Speech çerçevesi de tvOS'ta yok). Kullanıcı klavyeye girip dikte etmek istemedi; bu yüzden **iPhone mikrofon oluyor**: iPhone'daki Atlas'ta ••• → "TV'ye söyle", büyük düğmeye basılı tut, bırakınca metin TV'ye gider ve doğrudan tahmin olarak girer; TV sonucu telefona yollar. Telefon, TV'deki kategorinin yer adlarını (seçili dil + Türkçe) tanımaya ipucu (`contextualStrings`) olarak verir; tanıyıcının 4 alternatif yazımı da gider, ilk yazım bir yere uymazsa TV tam uyan alternatifi kullanır. Bırakınca kayıt 0,35 sn daha sürer (son hece kesilmesin); izinler verilmişse kayıt beklemeden başlar; ses oturumu `.playAndRecord` + varsayılan mod (otomatik kazanç) ve kayıt sırasında titreşime izin (`setAllowHapticsAndSystemSoundsDuringRecording`), titreşim üreteçleri önceden hazırlanır. Telefon ekranında sağ üstte sarı ampul (TV'de sıradaki ipucunu açar, kalan sayı rozetle), sol üstte oyun bitince "Yeni oyun" (TV'de alıştırma başlatır), altta küçük "Pes et" (ilk basış "Emin misin? Tekrar bas" der, 3 sn içinde ikinci basış pes eder). Ortada TV'nin kategorisi bir menü olarak görünür; buradan TV'nin kategorisi değiştirilir (`setCategory`). Telefondaki Atlas'ın kendi kategorisi TV'yi etkilemez; kullanıcı telefondan kategori değiştirince TV'nin Türkiye'de kaldığını bildirdi. TV `hintsLeft` ve `over`'ı yollar. Bu istekleri TV'de `TVVoiceBridge` (hep ekranda olan düzene bağlı) işler; tahmin kutusu oyun bitince ekrandan kalktığı için orada değil.
- Tanıma: ses aynı anda iki tanıyıcıya gider: sunucudaki genel tanıyıcı ve cihazda, kategorinin yer adlarıyla hazırlanan özel dil modeli (`SFCustomLanguageModelData`, iOS 17+, dil cihazda tanımayı destekliyorsa; önbellek `Caches/speech`). İkisinin bütün yazımları ve ara sonuçları (en çok 12) TV'ye gider. TV'nin eşleştirmesi (`voiceMatch([String])`) tek tek kelimeleri ("Kars ili"), sesçe sadeleştirmeyi (çift harf, ph/w/q/x) ve 1/3 harf farkını dener; tek ya da açık ara en yakın aday doğrudan tahmin edilir. Simülatörde 31 hatalı yazımla denendi ("Gümüşane", "Mula", "Elazık", "Antep" → doğru il; "Merhaba", "Tamam" → eşleşme yok).
- TV, Bonjour'da cihaz adıyla duyurulur (ör. "Oturma Odası"); telefon bağlandığı TV'nin adını gösterir. **Dikkat:** simülatör testi aynı ağdaki gerçek Apple TV'ye de bağlanabilir; testte `ATLAS_VOICE_TV="iMac"` kullan (simülatör TV, Mac'in adıyla duyurulur). TV'de klavyeyle dikte de hâlâ çalışır.
- Bağlantı Network çerçevesiyle (Bonjour + TCP). Önce MultipeerConnectivity denendi; iki simülatör arasında DTLS/UDP kanalı kurulamadı ("No route to host"), bu yüzden değiştirildi.
- Dikte sonucu hoşgörülü eşlenir: tam ad/takma ad/plaka → doğrudan tahmin; tek bir yerin başı → doğrudan tahmin; birkaç aday ya da 1–2 harf farkı → "Bunu mu demek istedin?" listesi. Başa eklenen tanımlıklar ("la France", "the Netherlands") atılır.
- Harita odaktayken yön tuşları kaydırır (kürede döndürür), ⏯ baştan gösterir; +/− düğmeleri yakınlaştırır. Paylaş düğmesi TV'de yok.
- Yardım metninde TV'ye özel iki satır var (`help.b1TV`, `help.practiceTV`).

**Marka (Claude Design "Atlas 1a · Küre-pin", proje 79684df1-…)**
- Renkler: turuncu #f26644, lacivert #142030, krem #f9f6f1. Logo: lacivert pin içinde krem küre, turuncu ekvator; koyu zeminde pin krem.
- İkon: turuncu zemin, lacivert pin (iOS koyu modda lacivert zemin, turuncu pin). 64/32/16 px'de işaret sadeleşir.
- Açılış animasyonu (pin düşer, dalga, "Atlas") her açılışta ~1,5 sn; ilk açılışta yardım ondan sonra gelir. Web'de veri gecikirse pin süzülür ve meridyen döner (yükleme animasyonu). Azaltılmış harekette animasyon yok.

**Puan ve seviyeler**
- Yalnızca kazanılan oyun puan getirir. Taban: 1 tahmin 200, 2 → 150, 3 → 120, sonra her tahminde −10 (en az 20). Günlük ×1,5; kategori: Dünya 1,5, Türkiye 1,2, Avrupa/Asya/Afrika 1, K. Amerika 0,8, G. Amerika/Okyanusya 0,6; her ipucu −%15; 5'in katına yuvarlanır.
- Seviye L'ye ulaşmak için toplam 125·L·(L−1) XP. Toplam XP saklanmaz, tüm kategorilerin geçmişinden hesaplanır (eski oyunlar ipucusuz sayılır). Mac/iPhone/TV ve web ayrı hesaplar (istatistikler ayrı olduğu için).
- Sonuç penceresinde seviye kartı: "+N XP", çubuk dolar; seviye atlanınca "SEVİYE ATLADIN", pin büyüyüp yeni numarayı gösterir. İstatistik penceresinin başında da seviye kartı var.

**İstatistikler**
- Takvim: son 18 hafta; günlükte yeşil tonu tahmin sayısını (≤3, ≤6, ≤10, fazlası), alıştırmada günlük oyun sayısını gösterir; pes edilen gün kırmızımsı.
- Keşfettiklerim: kategoride günlük + alıştırmada kazanılan oyunların gizli yerleri, sayaç ve yeşil boyalı küçük harita. Ek veri saklanmaz; oyun geçmişinden hesaplanır.

**Platformlar**
- Arkadaşlarla paylaşım için web seçildi (TestFlight ve DMG yerine). Yayın Vercel CLI ile yapılıyor; proje `atlas-bulmaca`, ekip `astoria6`, CLI kullanıcısı `azerozgur-6709`.
- iPhone'da öneri listesi düzeni itmeyen bir katman olarak açılır; harita sabit kalır, listenin sonu klavyenin altında kalabilir. Kullanıcı bunu özellikle istedi.
- Web'de tema düğmesi (sağ üst, ☀️/🌙) ve Ayarlar'da Sistem / Açık / Koyu seçimi var.

## Yarım kalan ve teklif edilen işler

- [ ] **Mac ve iPhone'a tema düğmesi:** Yalnızca web'de var; yerel uygulamalar sistem temasını izliyor. Teklif edildi, yanıt bekleniyor.
- [ ] **İstatistik senkronizasyonu:** Mac, iPhone ve web istatistikleri ayrı (web'de tarayıcı başına). iCloud ile senkronizasyon teklif edildi, yapılmadı.
- [ ] **Özel alan adı:** Örn. atlasbulmaca.com bağlamak teklif edildi, yapılmadı.
- [ ] **TestFlight / imzalı Mac DMG:** Seçenek olarak sunuldu; web seçildiği için yapılmadı.
- [ ] **Geliştirici imzası:** iPhone kurulumu geliştirici imzalı; yaklaşık 1 yılda süresi dolar.
- [ ] **Küçük bilinen kusur:** Dünya haritasında Kiribati'nin işareti, 180° boylamına yayıldığı için haritanın sol kenarında görünüyor.
- [ ] **"TV'ye söyle" gerçek cihazda:** Kullanıcı denedi, çalışıyor; ama bazı adları hâlâ doğru algılamadığını söyledi. İki aşamada iyileştirildi (ses oturumu/titreşim, sonra çift tanıyıcı + özel dil modeli + güçlü eşleştirme). Cihazda özel modelin Türkçe için çalışıp çalışmadığı (cihazda tanıma desteği) denenemedi; geri bildirim bekleniyor.
- **İmza notu:** Xcode'da Apple hesabı (ekip DR8AY52TR6) oturum açık olmalı. Yeni cihaz eklenirken `-allowProvisioningDeviceRegistration` gerekir. Apple yeni lisans sözleşmesi çıkarınca derleme "PLA Update available" hatası verir; kullanıcı developer.apple.com/account'ta kabul etmeli.
- [ ] **Geliştirme kancaları:** `DebugSnapshots.swift` (`-renderSnapshots`), `ATLAS_PREFILL` ortam değişkeni (tahmin kutusunu önceden doldurur) ve TV'de `ATLAS_VOICETEST` / `ATLAS_GUESSES` / `ATLAS_PRACTICE` / `ATLAS_WIN` / `ATLAS_SWITCH="europe@8"` (dikte eşleştirmesini simülatörde dener; simctl'de `SIMCTL_CHILD_` önekiyle), iPhone'da `ATLAS_VOICE_SEND="Ankara|Merhaba/Kars|hint|giveup|newgame"` ("TV'ye söyle"yi açar, bağlanınca metinleri mikrofonsuz gönderir; "/" sonrası alternatif yazımlar; `hint`, `giveup`, `newgame` düğmeler, `cat:europe` kategori seçimi) ve `ATLAS_VOICE_TV` (yalnızca adı bunu içeren TV'ye bağlanır; TV ve iPhone simülatörü birlikte çalışır) yalnızca Debug derlemesinde var; yayın derlemesinde etkisizler ama istenirse kaldırılabilir. Web'de yerel sunucuda (127.0.0.1) `window.atlasGame` oyun nesnesini açar (CDP testleri için).
