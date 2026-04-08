# Native Uygulama Master Dokümanı

Bu doküman, `Another IPTV Player` için iOS uygulamasını referans alarak tüm native platformlarda aynı ürün deneyimini sunmak amacıyla hazırlanmış ana kılavuzdur.

## 1) Hedef ve Kapsam

- Tek ürün, çok platform: iOS, Android, Apple TV, Android TV, Google TV, macOS, Windows, Linux.
- Her platformda aynı temel yetenek seti (playlist, canlı TV, VOD, diziler, arama, favoriler, geçmiş, player kontrolü).
- Farklı platformlarda UI kalıpları doğal kalabilir, ancak davranış ve iş kuralları aynı olmalıdır.

## 2) Platformlar ve Parite Politikası

## 2.1 Desteklenecek Platformlar

- Mobil: iOS, Android
- TV: Apple TV, Android TV, Google TV
- Masaüstü: macOS, Windows, Linux

## 2.2 Özellik Paritesi Kuralları

- **P0 (zorunlu):** Playlist ekleme/doğrulama, içerik listeleme, oynatma, favori, geçmiş, arama.
- **P1 (yüksek):** EPG, altyazı özelleştirme, track seçimi hafızası, PiP (destekleyen platformda).
- **P2 (opsiyonel):** Gelişmiş debug overlay, gelişmiş kanal tarayıcı önizleme, platform-spesifik kısayollar.

Parite metriği:
- Yeni bir özellik merge olmadan önce platform bazlı parity checklist’i geçmeli.
- Özellik davranışı için tek kaynak doküman ve ortak test senaryosu kullanılmalı.

## 3) Ürün Mimarisi (Yüksek Seviye)

- **Presentation Layer:** SwiftUI/Jetpack Compose/desktop UI katmanları.
- **Domain Layer:** Playlist yönetimi, içerik filtreleme, geçmiş/favori kuralları, arama.
- **Data Layer:** API istemcileri, cache, lokal veritabanı.
- **Playback Layer:** mpv/media engine köprüsü, track yönetimi, PiP, timeline, gesture kontrolü.

Öneri:
- İş kuralları platformlar arası ortak dokümanda ve testlerde tanımlanmalı.
- API modelleri mümkün olduğunca eşlenik tutulmalı (aynı alan isimleri, aynı hata kodu haritası).

## 4) Ekranlar (Uçtan Uca)

## 4.1 Onboarding / Playlist Yönetimi

- Playlist listesi ekranı
- Playlist ekle/düzenle ekranı
- Playlist doğrulama ve ilk senkron progress ekranı
- Hata/yeniden dene durumları

Zorunlu alanlar:
- Playlist adı
- Server URL
- Username
- Password

Doğrulama:
- URL normalize edilir (`http/https`, trailing slash, endpoint tamamlanır).
- Kimlik doğrulama sonucu doğrulanır.
- Başarılıysa kategori + içerik senkronizasyonu başlar.

## 4.2 Dashboard / Ana Sekmeler

- Canlı TV
- Filmler
- Diziler
- Arama
- Ayarlar

Her sekmede:
- Kategori filtreleme
- Poster/liste görünümü
- Detay sayfasına geçiş
- Favori aksiyonu

## 4.3 İçerik Detay Ekranları

- Film detay
- Dizi detay (sezon/bölüm)
- Canlı kanal detay veya hızlı bilgi kartı

Detayda:
- Özet, görsel, metadata
- Oynat butonu
- Favori durumu
- Devamdan oynat bilgisi

## 4.4 Oynatıcı Ekranı

- Tam ekran video yüzeyi
- Üst kontrol barı (geri, başlık, ayarlar, altyazı, PiP)
- Merkez kontrol (play/pause, 15sn geri/ileri)
- Alt kontrol (timeline, süre, bölüm/kanal geçişi)
- Dikey kenar slider’ları (ses/parlaklık gibi)

## 4.5 Yardımcı Ekranlar

- Favoriler
- İzleme geçmişi / Continue watching
- EPG rehberi
- Uygulama ayarları
- Arama sonuçları (live/vod/series birleşik)

## 5) Entegrasyonlar

## 5.1 Zorunlu Entegrasyonlar

- **Xtream Codes API**
  - Kimlik doğrulama
  - Kategori endpoint’leri
  - Live/VOD/Series listeleri
  - İçerik detay endpoint’leri
- **XMLTV EPG**
  - Kanal EPG ID eşleme
  - Disk + bellek cache
  - TTL sonrası arka plan yenileme
- **Player Engine (mpv/media kit)**
  - Stream açma
  - Track listesi
  - Seek, playback speed, aspect mode
  - PiP

## 5.2 Orta Vadeli Entegrasyonlar

- M3U/M3U8 playlist import
- Harici altyazı kaynakları
- Uzaktan kumanda/TV odaklı giriş modeli
- Crash/analytics telemetry (opt-in, gizlilik dostu)

## 6) Entegrasyon Adımları (Implementasyon Sırası)

## 6.1 Playlist + Auth

1. Playlist formunu hazırla.
2. URL normalize et.
3. Auth endpoint’i ile bağlantıyı doğrula.
4. Başarılıysa playlist kaydını lokal DB’ye yaz.

## 6.2 İlk İçerik Senkronizasyonu

1. Live/VOD/Series kategorilerini çek.
2. Live/VOD/Series stream listelerini çek.
3. Tüm veriyi tek transaction veya güvenli batch ile DB’ye yaz.
4. UI’da progress adımlarını göster.
5. Hata durumunda kullanıcıya anlaşılır mesaj + retry ver.

## 6.3 EPG

1. `xmltv` endpoint’inden guide al.
2. Parse edip kanal ID bazlı indeksle.
3. Bellek cache + disk cache’e yaz.
4. TTL dolduğunda arka planda sessiz yenile.
5. Ağ hatasında son geçerli disk cache’i fallback kullan.

## 6.4 Player

1. Oynatıcı container kur.
2. Playback state akışını bağla (loading, playing, paused, ended, error).
3. Track seçim sheet’lerini bağla.
4. Subtitle appearance ayarlarını uygula.
5. Timeline ve seek davranışını finalize et.
6. Watch history timer ile periyodik kaydet.

## 7) Player Özellik Seti

- Live ve VOD/Series oynatma
- Resume from last position
- Continue watching kaydı
- 15s geri/ileri
- Bölüm önceki/sonraki geçişi
- Canlı kanal önceki/sonraki geçişi
- Kanal tarayıcı (kategori + önizleme)
- Audio/video/subtitle track seçimi
- Track tercihi hafızası (başlık/seri bazlı)
- Subtitle style özelleştirme
- Aspect ratio modları
- Gesture ile zoom/pan
- PiP (destekli platformlar)
- Playback debug overlay (opsiyonel)

## 8) Playlist Oluşturma ve Yönetim Akışı

## 8.1 Xtream Playlist

1. Kullanıcı formu doldurur.
2. Uygulama credentials doğrular.
3. Senkronizasyon başlar.
4. Kategori + içerikler lokal DB’ye yazılır.
5. Dashboard sekmeleri aktifleşir.

## 8.2 M3U/M3U8 Playlist (Parite Hedefi)

1. Kullanıcı URL veya dosya import seçer.
2. M3U parser ile kanal/film/dizi etiketleri çıkarılır.
3. Gerekli metadata normalize edilir.
4. Lokal DB şemasına map edilir.
5. EPG URL varsa XMLTV ile eşlenir.

## 8.3 Playlist Güncelleme

- Kullanıcı “yeniden senkronize et” aksiyonu alır.
- Eski kayıtlar version/tag ile güvenli biçimde güncellenir.
- UI’da kademeli durum gösterilir (indiriliyor, kaydediliyor, tamamlandı).

## 9) Veri Modeli ve Lokal Depolama

- Playlist
- Category (live/vod/series)
- LiveStream / VODStream / Series
- Series Episode
- WatchHistory
- Favorites
- XMLTV Cache
- Playback Track Preferences

Kurallar:
- Tüm kayıtlar `playlistId` ile namespace edilir.
- Çoklu playlist senaryosunda veri izolasyonu zorunludur.
- DB migration’ları geriye uyumlu tasarlanır.

## 10) Non-Functional Gereksinimler

- İlk playlist senkronizasyonunda kullanıcıya progress geri bildirimi
- Büyük playlistlerde bellek kullanım kontrolü
- Ağ kesintisinde güvenli retry + timeout
- Uygulama yeniden açıldığında hızlı cold start
- Player crash/lockup senaryolarında güvenli fallback

## 11) Test Stratejisi

- **Unit tests:** URL builder, parser, playlist doğrulama, track preference kuralları.
- **Integration tests:** Xtream auth, içerik çekme, DB yazım, EPG parse/cache.
- **UI tests:** Playlist ekleme, tab geçişleri, oynatıcı kontrolleri, favori/geçmiş.
- **Parity tests:** Aynı senaryonun tüm platformlarda aynı sonuç verdiğini doğrulayan checklist.

## 12) Sürümleme ve Teslimat

- Sürüm notları her platform için tek formatta yazılır.
- P0 parity tamamlanmadan “stable” etiketi verilmez.
- Yeni özelliklerde rollout sırası:
  1) iOS referans implementasyon
  2) Android parity
  3) Desktop parity

## 13) Yol Haritası (Öneri)

- **Faz 1:** Playlist + Dashboard + Player temel set + favori/geçmiş
- **Faz 2:** EPG + arama + subtitle/track preference gelişimi
- **Faz 3:** M3U tam desteği + TV/remote optimizasyonları + gelişmiş telemetry

## 14) Tanımlar

- **Parite:** Özelliğin tüm hedef platformlarda aynı iş kuralı ve kullanıcı sonucu üretmesi.
- **P0/P1/P2:** Özellik öncelik sınıfı.
- **Fallback cache:** Ağ başarısız olduğunda en son geçerli lokal verinin kullanımı.
