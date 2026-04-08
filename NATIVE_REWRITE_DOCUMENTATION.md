# Another IPTV Player - Native Rewrite Dokümantasyonu

> Bu doküman, mevcut Flutter IPTV Player projesinin native platformlara (Android/iOS/TV) yeniden yazılması için hazırlanmış kapsamlı bir referans dokümandır.

**Mevcut Versiyon:** 1.3.0+21  
**Flutter SDK:** ^3.9.2  
**Desteklenen Platformlar:** Android, iOS, macOS, Windows, Linux, Web

---

## 1. Proje Mimarisi (Architecture Overview)

### 1.1 Katmanlı Mimari

```
┌─────────────────────────────────────────────┐
│                   UI Layer                   │
│         (Screens / Widgets / Pages)          │
├─────────────────────────────────────────────┤
│              Controller Layer                │
│     (ChangeNotifier + Provider Pattern)      │
├─────────────────────────────────────────────┤
│             Repository Layer                 │
│   (IptvRepository / M3uRepository / etc.)    │
├─────────────────────────────────────────────┤
│              Service Layer                   │
│  (DatabaseService / WatchHistoryService /    │
│   PlaylistService / ContentService)          │
├─────────────────────────────────────────────┤
│              Database Layer                  │
│        (Drift ORM - SQLite / WASM)           │
└─────────────────────────────────────────────┘
```

### 1.2 Dizin Yapısı

```
lib/
├── main.dart                    # Entry point, MultiProvider, MaterialApp
├── controllers/                 # 11 ChangeNotifier (state management)
│   ├── category_detail_controller.dart
│   ├── favorites_controller.dart
│   ├── iptv_controller.dart
│   ├── live_stream_controller.dart
│   ├── locale_provider.dart
│   ├── m3u_controller.dart
│   ├── m3u_home_controller.dart
│   ├── playlist_controller.dart
│   ├── theme_provider.dart
│   ├── watch_history_controller.dart
│   └── xtream_code_home_controller.dart
├── database/                    # Drift ORM tanımları
│   ├── database.dart            # 15 tablo tanımı + tüm query metodları
│   ├── database.g.dart          # Auto-generated code
│   ├── drift_flutter.dart
│   └── connection/              # Platform-specific DB bağlantıları
│       ├── connect.dart
│       ├── native.dart
│       ├── unsupported.dart
│       └── web.dart
├── models/                      # 21 veri modeli
├── repositories/                # 4 repository
│   ├── iptv_repository.dart     # Xtream Codes API entegrasyonu
│   ├── m3u_repository.dart      # M3U veri erişimi
│   ├── favorites_repository.dart
│   └── user_preferences.dart    # SharedPreferences wrapper
├── screens/                     # 25 ekran
├── services/                    # 10 servis
│   ├── app_state.dart           # Statik global state
│   ├── content_service.dart     # İçerik routing
│   ├── database_service.dart    # DB wrapper
│   ├── event_bus.dart           # Widget-arası event sistemi
│   ├── m3u_parser.dart          # M3U dosya/URL parser
│   ├── player_state.dart
│   ├── playlist_content_state.dart
│   ├── playlist_service.dart
│   ├── service_locator.dart     # GetIt DI setup
│   └── watch_history_service.dart
├── utils/                       # 13 yardımcı
├── widgets/                     # 34 reusable widget
└── l10n/                        # 10 dil desteği (ARB dosyaları)
```

### 1.3 Dependency Injection

- **GetIt** (service locator pattern): `AppDatabase` singleton ve `MyAudioHandler` register edilir
- **Provider** (state management): `MultiProvider` ile global state (`LocaleProvider`, `PlaylistController`, `ThemeProvider`)
- **AppState** (static fields): `currentPlaylist`, `xtreamCodeRepository`, `m3uRepository`, `m3uItems` — navigation ve repository köprüsü

### 1.4 Uygulama Başlatma Akışı

```
main()
  → setupServiceLocator()
    → WidgetsFlutterBinding.ensureInitialized()
    → GetIt: AppDatabase singleton register
    → GetIt: MyAudioHandler register
    → MediaKit.ensureInitialized()
  → runApp(MultiProvider)
    → LocaleProvider
    → PlaylistController
    → ThemeProvider
    → MaterialApp(home: AppInitializerScreen)
      → UserPreferences.getLastPlaylist()
        → Playlist varsa → XtreamCodeHomeScreen veya M3UHomeScreen
        → Yoksa → PlaylistScreen
```

---

## 2. IPTV Entegrasyon Tipleri

Uygulama **iki ana IPTV kaynak tipini** destekler:

### 2.1 Playlist Tipleri

| Tip | Enum | Açıklama |
|-----|------|----------|
| **Xtream Codes** | `PlaylistType.xtream` | API tabanlı; sunucu URL + kullanıcı adı + şifre |
| **M3U / M3U8** | `PlaylistType.m3u` | Dosya tabanlı; URL veya yerel dosya |

### 2.2 İçerik Tipleri

| Tip | Enum | Açıklama |
|-----|------|----------|
| **Live TV** | `ContentType.liveStream` | Canlı yayın kanalları |
| **VOD (Film)** | `ContentType.vod` | İsteğe bağlı video (filmler) |
| **Series (Dizi)** | `ContentType.series` | Dizi, sezon ve bölüm yapısı |

### 2.3 Kategori Tipleri

| Tip | Enum | Açıklama |
|-----|------|----------|
| **Live** | `CategoryType.live` | Canlı yayın kategorileri |
| **VOD** | `CategoryType.vod` | Film kategorileri |
| **Series** | `CategoryType.series` | Dizi kategorileri |

---

## 3. Xtream Codes API Entegrasyonu

### 3.1 API Yapılandırması

```
Base URL: {sunucu_url}/player_api.php
Auth: ?username={username}&password={password}
Method: GET
Content-Type: application/json
```

**ApiConfig modeli:**
- `baseUrl` — sunucu root URL'i (ör: `http://host:port`)
- `username` — kullanıcı adı
- `password` — şifre
- `baseParams` — `{username, password}` map'i (her isteğe eklenir)

### 3.2 API Endpoint'leri

| Endpoint | Action | Amaç | Dönen Veri |
|----------|--------|------|-----------|
| `player_api.php` | *(yok — login)* | Kimlik doğrulama + sunucu/kullanıcı bilgisi | `user_info` + `server_info` |
| `player_api.php` | `get_live_categories` | Canlı yayın kategorileri | `[{category_id, category_name, parent_id}]` |
| `player_api.php` | `get_vod_categories` | Film kategorileri | Aynı format |
| `player_api.php` | `get_series_categories` | Dizi kategorileri | Aynı format |
| `player_api.php` | `get_live_streams` | Canlı yayın listesi | `[{stream_id, name, stream_icon, category_id, epg_channel_id}]` |
| `player_api.php` | `get_vod_streams` | Film listesi | `[{stream_id, name, stream_icon, category_id, rating, container_extension, ...}]` |
| `player_api.php` | `get_series` | Dizi listesi | `[{series_id, name, cover, plot, genre, rating, ...}]` |
| `player_api.php` | `get_vod_info` | Film detayı | `{info: {…}, movie_data: {…}}` |
| `player_api.php` | `get_series_info` | Dizi detayı (sezonlar + bölümler) | `{info, seasons[], episodes{seasonKey: [...]}}` |

### 3.3 Xtream Codes Veri Yükleme Sırası

```
loadAllData()
  1. loadUserInfo()         → player_api.php (no action) → UserInfo + ServerInfo
  2. loadCategories()       → get_live_categories + get_vod_categories + get_series_categories (paralel)
  3. loadLiveChannels()     → get_live_streams
  4. loadMovies()           → get_vod_streams
  5. loadSeries()           → get_series
```

Her adım bir `ProgressStep` enum değerine karşılık gelir ve UI'da ilerleme göstergesi olarak kullanılır:
- `ProgressStep.userInfo`
- `ProgressStep.categories`
- `ProgressStep.liveChannels`
- `ProgressStep.movies`
- `ProgressStep.series`

### 3.4 Xtream Stream URL Yapısı

Stream URL'leri API'den direkt gelmez, istemci tarafında oluşturulur:

```
Live:   {server_url}/{username}/{password}/{stream_id}
VOD:    {server_url}/movie/{username}/{password}/{stream_id}.{container_extension}
Series: {server_url}/series/{username}/{password}/{episode_id}.{container_extension}
```

### 3.5 Xtream Cache Stratejisi

- İlk yüklemede tüm veri API'den çekilip SQLite'a yazılır
- Sonraki açılışlarda önce DB'den okunur, veri varsa API çağrısı yapılmaz
- `forceRefresh = true` ile cache bypass edilir
- Kategorilerde upsert (`insertAllOnConflictUpdate`), stream'lerde delete + insert
- Series detail için `lastModified` karşılaştırmalı smart cache

### 3.6 Xtream API Response Modelleri

**UserInfo:**
```
username, password, message, auth (int), status,
expDate, isTrial, activeCons, createdAt,
maxConnections, allowedOutputFormats (List<String>)
```

**ServerInfo:**
```
url, port, httpsPort, serverProtocol, rtmpPort,
timezone, timestampNow (int), timeNow
```

---

## 4. M3U / M3U8 Parser Entegrasyonu

### 4.1 M3U Format Yapısı

```m3u
#EXTM3U
#EXTINF:-1 tvg-id="channel1" tvg-name="Channel 1" tvg-logo="http://logo.png" group-title="Sports",Channel 1 HD
http://stream-url.com/live/channel1.ts
#EXTGRP:Entertainment
#EXTINF:-1 tvg-id="channel2",Channel 2
http://stream-url.com/live/channel2.m3u8
```

### 4.2 Parse Edilen Attribute'lar

| Attribute | Kaynak | Açıklama |
|-----------|--------|----------|
| `tvg-id` | `#EXTINF` | EPG kanal ID'si |
| `tvg-name` | `#EXTINF` | EPG kanal adı |
| `tvg-logo` | `#EXTINF` | Kanal logosu URL'i |
| `tvg-url` | `#EXTINF` | EPG veri kaynağı URL'i |
| `tvg-rec` | `#EXTINF` | Catch-up/kayıt desteği |
| `tvg-shift` | `#EXTINF` | Zaman kayması (timeshift) |
| `group-title` | `#EXTINF` | Grup/kategori adı |
| `user-agent` | `#EXTINF` | Özel User-Agent header |
| `group-name` | `#EXTGRP:` | Alternatif grup adı |

### 4.3 Parse Algoritması

```
1. İçeriği satırlara böl (\n ile split)
2. Her satırı trim et
3. Satır döngüsü:
   a. #EXTINF ile başlıyorsa:
      - İlk virgülden öncesi: metadata (attribute'lar)
      - İlk virgülden sonrası: kanal adı
      - Regex ile attribute'ları çıkar: attr="(.*?)"
   b. #EXTGRP: ile başlıyorsa:
      - group-name olarak kaydet
   c. Boş değilse ve # ile başlamıyorsa:
      - Bu satır stream URL'idir
      - Biriktirilen metadata + URL → M3uItem oluştur
      - UUID ile benzersiz ID ata
      - İçerik tipini URL'den tespit et
      - Metadata'yı temizle
```

### 4.4 İçerik Tipi Tespiti (M3U)

URL string'inden heuristic tespit:
```
URL "movie" içeriyorsa    → ContentType.vod
URL "series" içeriyorsa   → ContentType.series
Diğer tüm durumlar       → ContentType.liveStream
```

> **Not:** Bu yöntem %100 doğru değildir. Native rewrite'da daha gelişmiş bir tespit mekanizması düşünülebilir (ör: uzantıya bakma, kodek probing).

### 4.5 M3U Kaynak Tipleri

| Tip | Yöntem | Açıklama |
|-----|--------|----------|
| **URL** | `HttpClient GET` | Uzak M3U dosyasını indir ve parse et |
| **Dosya** | `File.readAsString(utf8)` | Yerel `.m3u` / `.m3u8` dosyasını oku |

### 4.6 M3U Series Gruplandırma

M3U'da dizi yapısı doğrudan yoktur. Uygulama, kanal adından regex ile sezon/bölüm bilgisi çıkarır:

**Desteklenen formatlar:**
```
"Show Name S01 E001"                 → Regex: ^(.+?)\s+S(\d{1,2})\s+E(\d{1,3})
"Show Name Season 1 Episode 3"      → Regex: ^(.+?)\s+Season\s+(\d{1,2})\s+Episode\s+(\d{1,3})
```

**Gruplandırma:**
- Aynı series name → `M3uSerie`
- Season + Episode numarası → `M3uEpisode`
- Series ID: `{playlistId}_{series_name_lowercase_underscored}`

### 4.7 M3U Post-Parse Pipeline

```
M3U Parse
  → M3uItem listesi
  → groupTitle'a göre Category oluştur (her ContentType için ayrı)
  → Her item'a categoryId ata
  → DB'ye batch insert (m3uItems + categories)
  → Series tipi olanlar için SeriesParser çalıştır
  → M3uSerie + M3uEpisode oluştur ve DB'ye kaydet
```

---

## 5. EPG (Elektronik Program Rehberi)

### 5.1 Mevcut Durum

- **Xtream:** `epg_channel_id` alanı API'den alınıp `LiveStream` modeline ve DB'ye kaydedilir, ancak EPG verisi (program listesi) çekilmez
- **M3U:** `tvg-id`, `tvg-url` parse edilip saklanır ama XMLTV fetch/parse yapılmaz
- **UI'da sadece** `epg_channel_id` bilgi olarak gösterilir

### 5.2 Native Rewrite İçin EPG Önerileri

Tam EPG desteği için:

**Xtream Codes EPG:**
```
GET {server}/xmltv.php?username={u}&password={p}
→ XMLTV format (XML)

GET player_api.php?action=get_short_epg&stream_id={id}&limit=10
→ Kısa EPG (JSON)

GET player_api.php?action=get_simple_data_table&stream_id={id}
→ Tam EPG tablosu (JSON)
```

**M3U EPG:**
```
tvg-url attribute'undaki URL'den XMLTV dosyası indir
XMLTV XML → parse → programme elementleri → DB
```

---

## 6. Veritabanı Şeması

### 6.1 Tablo Listesi (15 tablo, schema version: 8)

#### Playlists
| Kolon | Tip | PK | Nullable | Açıklama |
|-------|-----|-----|----------|----------|
| id | TEXT | PK | | UUID |
| name | TEXT | | | Playlist adı |
| type | TEXT | | | `PlaylistType.xtream` veya `PlaylistType.m3u` |
| url | TEXT | | Yes | Sunucu URL veya M3U URL |
| username | TEXT | | Yes | Xtream kullanıcı adı |
| password | TEXT | | Yes | Xtream şifresi |
| createdAt | DATETIME | | | Oluşturma tarihi |

#### Categories
| Kolon | Tip | PK | Açıklama |
|-------|-----|-----|----------|
| categoryId | TEXT | PK (composite) | Kategori ID |
| categoryName | TEXT | | Kategori adı |
| parentId | INTEGER | | Üst kategori (default: 0) |
| playlistId | TEXT | PK (composite) | İlişkili playlist |
| type | TEXT | PK (composite) | `live` / `vod` / `series` |
| createdAt | DATETIME | | |
| updatedAt | DATETIME | | |

#### LiveStreams
| Kolon | Tip | PK | Açıklama |
|-------|-----|-----|----------|
| streamId | TEXT | PK (composite) | Stream ID |
| name | TEXT | | Kanal adı |
| streamIcon | TEXT | | Logo URL |
| categoryId | TEXT | | Kategori referansı |
| epgChannelId | TEXT | | EPG kanal ID |
| playlistId | TEXT | PK (composite) | Playlist referansı |
| createdAt | DATETIME | | |

#### VodStreams
| Kolon | Tip | PK | Açıklama |
|-------|-----|-----|----------|
| streamId | TEXT | PK (composite) | Stream ID |
| name | TEXT | | Film adı |
| streamIcon | TEXT | | Poster URL |
| categoryId | TEXT | | Kategori |
| rating | TEXT | | Rating string |
| rating5based | REAL | | 5 üzerinden puan |
| containerExtension | TEXT | | Dosya uzantısı (mp4, mkv, avi) |
| playlistId | TEXT | PK (composite) | Playlist |
| genre | TEXT | Yes | Tür (v8'de eklendi) |
| youtubeTrailer | TEXT | Yes | Trailer URL (v8'de eklendi) |
| createdAt | DATETIME | | |

#### SeriesStreams (Dizi Listesi)
| Kolon | Tip | Açıklama |
|-------|-----|----------|
| seriesId | TEXT (PK) | Dizi ID |
| name | TEXT | Dizi adı |
| cover | TEXT? | Kapak resmi |
| plot | TEXT? | Özet |
| cast | TEXT? | Oyuncular |
| director | TEXT? | Yönetmen |
| genre | TEXT? | Tür |
| releaseDate | TEXT? | Yayın tarihi |
| rating | TEXT? | Rating |
| rating5based | REAL? | 5 üzerinden puan |
| youtubeTrailer | TEXT? | Trailer |
| episodeRunTime | TEXT? | Bölüm süresi |
| categoryId | TEXT? | Kategori |
| playlistId | TEXT (PK) | Playlist |
| lastModified | TEXT? | Son güncelleme (cache kontrolü) |
| backdropPath | TEXT? | Arka plan resmi (JSON string) |
| createdAt | DATETIME | |

#### SeriesInfos (Dizi Detayı)
| Kolon | Tip | Açıklama |
|-------|-----|----------|
| id | INTEGER (AI) | Auto-increment PK |
| seriesId | TEXT | Dizi ID |
| name, cover, plot, cast, director, genre | TEXT? | Metadata |
| releaseDate, lastModified, rating | TEXT? | |
| rating5based | INTEGER? | |
| backdropPath | TEXT? | |
| youtubeTrailer | TEXT? | |
| episodeRunTime | TEXT? | |
| categoryId | TEXT? | |
| playlistId | TEXT | |

#### Seasons
| Kolon | Tip | Açıklama |
|-------|-----|----------|
| id | INTEGER (AI) | PK |
| seriesId | TEXT | Dizi referansı |
| airDate | TEXT? | Yayın tarihi |
| episodeCount | INTEGER? | Bölüm sayısı |
| seasonId | INTEGER | API'den gelen sezon ID |
| name | TEXT | Sezon adı |
| overview | TEXT? | Özet |
| seasonNumber | INTEGER | Sezon numarası |
| voteAverage | INTEGER? | Oylama ortalaması |
| cover, coverBig | TEXT? | Sezon kapağı |
| playlistId | TEXT | |

#### Episodes
| Kolon | Tip | Açıklama |
|-------|-----|----------|
| id | INTEGER (AI) | PK |
| seriesId | TEXT | Dizi referansı |
| episodeId | TEXT | API'den gelen bölüm ID |
| episodeNum | INTEGER | Bölüm numarası |
| title | TEXT | Bölüm başlığı |
| containerExtension | TEXT? | Dosya uzantısı |
| season | INTEGER | Sezon numarası |
| customSid, added, directSource | TEXT? | Ek alanlar |
| playlistId | TEXT | |
| tmdbId | INTEGER? | TMDB referansı |
| releasedate, plot, duration | TEXT? | |
| durationSecs | INTEGER? | Süre (saniye) |
| movieImage | TEXT? | Bölüm resmi |
| bitrate | INTEGER? | |
| rating | REAL? | |

#### WatchHistories
| Kolon | Tip | PK | Açıklama |
|-------|-----|-----|----------|
| playlistId | TEXT | PK (composite) | |
| contentType | INTEGER | | Enum index (0=live, 1=vod, 2=series) |
| streamId | TEXT | PK (composite) | |
| seriesId | TEXT? | | Dizi bölümleri için |
| watchDuration | INTEGER? | | İzlenen süre (ms) |
| totalDuration | INTEGER? | | Toplam süre (ms) |
| lastWatched | DATETIME | | Son izleme |
| imagePath | TEXT? | | Thumbnail |
| title | TEXT | | Başlık |

#### M3uItems
| Kolon | Tip | PK | Açıklama |
|-------|-----|-----|----------|
| id | TEXT | PK | UUID |
| playlistId | TEXT | | |
| url | TEXT | | Stream URL |
| name | TEXT? | | Kanal adı |
| tvgId | TEXT? | | EPG ID |
| tvgName | TEXT? | | EPG adı |
| tvgLogo | TEXT? | | Logo URL |
| tvgUrl | TEXT? | | EPG kaynak URL |
| tvgRec | TEXT? | | Catch-up |
| tvgShift | TEXT? | | Timeshift |
| groupTitle | TEXT? | | Grup adı |
| groupName | TEXT? | | Alternatif grup |
| userAgent | TEXT? | | Özel UA |
| referrer | TEXT? | | Referrer header |
| categoryId | TEXT? | | Atanan kategori |
| contentType | INTEGER | | Enum index |
| createdAt, updatedAt | DATETIME | | |

**Constraints:** `CHECK (LENGTH(id) > 0)`, `CHECK (LENGTH(url) > 0)`, `CHECK (LENGTH(playlist_id) > 0)`

#### M3uSeries
| Kolon | Tip | PK | Açıklama |
|-------|-----|-----|----------|
| playlistId | TEXT | PK (composite) | |
| seriesId | TEXT | PK (composite) | Generated ID |
| name | TEXT | | Dizi adı |
| categoryId | TEXT? | | |
| cover | TEXT? | | |

#### M3uEpisodes
| Kolon | Tip | PK | Açıklama |
|-------|-----|-----|----------|
| playlistId | TEXT | PK (composite) | |
| seriesId | TEXT | PK (composite) | |
| seasonNumber | INTEGER | PK (composite) | |
| episodeNumber | INTEGER | PK (composite) | |
| name | TEXT | | Bölüm adı |
| url | TEXT | | Stream URL |
| categoryId | TEXT? | | |
| cover | TEXT? | | |

#### Favorites
| Kolon | Tip | PK | Açıklama |
|-------|-----|-----|----------|
| id | TEXT | PK | UUID |
| playlistId | TEXT | | |
| contentType | INTEGER | | Enum index |
| streamId | TEXT | | İçerik referansı |
| episodeId | TEXT? | | Bölüm referansı (opsiyonel) |
| m3uItemId | TEXT? | | M3U item referansı (opsiyonel) |
| name | TEXT | | |
| imagePath | TEXT? | | |
| createdAt, updatedAt | DATETIME | | |

#### UserInfos
| Kolon | Tip | Açıklama |
|-------|-----|----------|
| id | INTEGER (AI) | PK |
| playlistId | TEXT | |
| username, password | TEXT | Xtream credentials |
| message, status, expDate | TEXT | Hesap bilgileri |
| auth | INTEGER | Auth durumu |
| isTrial, activeCons, maxConnections | TEXT | Abonelik bilgileri |
| allowedOutputFormats | TEXT | Virgülle ayrılmış format listesi |
| createdAt | TEXT | |

#### ServerInfos
| Kolon | Tip | Açıklama |
|-------|-----|----------|
| id | INTEGER (AI) | PK |
| playlistId | TEXT | |
| url, port, httpsPort | TEXT | Sunucu adresleri |
| serverProtocol | TEXT | http/https |
| rtmpPort | TEXT | RTMP port |
| timezone, timeNow | TEXT | Zaman bilgisi |
| timestampNow | INTEGER | Unix timestamp |

### 6.2 Migration Geçmişi

| Version | Değişiklik |
|---------|-----------|
| 1 → 2 | categories, userInfos, serverInfos, liveStreams, vodStreams, seriesStreams, seriesInfos, seasons, episodes, watchHistories oluşturuldu |
| 2 → 3 | Playlist type `xstream` → `xtream` düzeltmesi |
| 3 → 4 | m3uItems tablosu eklendi |
| 4 → 5 | m3uSeries, m3uEpisodes tabloları eklendi |
| 5 → 6 | m3uItems drop + recreate (şema değişikliği) |
| 6 → 7 | favorites tablosu eklendi |
| 7 → 8 | vodStreams'e `genre` ve `youtubeTrailer` kolonları eklendi |

---

## 7. Veri Akış Diyagramları

### 7.1 Xtream Codes Veri Akışı

```
┌──────────────┐     HTTP GET      ┌──────────────┐
│  Xtream API  │ ←──────────────── │IptvRepository │
│  (Sunucu)    │ ─────────────────→│              │
└──────────────┘   JSON Response   │  .getPlayer  │
                                   │  .getLive*   │
                                   │  .getMovies* │
                                   │  .getSeries* │
                                   └──────┬───────┘
                                          │ Domain Model
                                          ↓
                                   ┌──────────────┐
                                   │  AppDatabase  │
                                   │  (SQLite)    │
                                   └──────┬───────┘
                                          │ Read
                                          ↓
                                   ┌──────────────┐
                                   │IptvController │ ← ChangeNotifier
                                   │  (Provider)  │
                                   └──────┬───────┘
                                          │ notifyListeners()
                                          ↓
                                   ┌──────────────┐
                                   │   UI Screen   │
                                   └──────────────┘
```

### 7.2 M3U Veri Akışı

```
┌──────────────┐   HTTP / File     ┌──────────────┐
│   M3U URL    │ ──────────────── → │  M3uParser   │
│  veya Dosya  │                   │  (Isolate)   │
└──────────────┘                   └──────┬───────┘
                                          │ List<M3uItem>
                                          ↓
                                   ┌──────────────┐
                                   │M3uController  │
                                   │  - Kategori   │
                                   │    oluştur   │
                                   │  - Series     │
                                   │    grupla    │
                                   └──────┬───────┘
                                          │ Insert
                                          ↓
                                   ┌──────────────┐
                                   │  AppDatabase  │
                                   │  (m3uItems,  │
                                   │  categories, │
                                   │  m3uSeries,  │
                                   │  m3uEpisodes)│
                                   └──────┬───────┘
                                          │ Read
                                          ↓
                                   ┌──────────────┐
                                   │M3uRepository  │ → ContentItem
                                   └──────┬───────┘
                                          ↓
                                   ┌──────────────┐
                                   │   UI Screen   │
                                   └──────────────┘
```

### 7.3 ContentItem — Unified Model

`ContentItem` uygulamanın tüm içerik tiplerini birleştiren ana UI modelidir:

```
ContentItem
├── id: String (streamId veya m3uItem.id)
├── url: String (late — constructor'da hesaplanır)
│   ├── Xtream → buildMediaUrl(this)
│   └── M3U → m3uItem.url
├── name: String
├── imagePath: String
├── description: String?
├── duration: Duration?
├── coverPath: String?
├── containerExtension: String?
├── contentType: ContentType
├── liveStream: LiveStream?       (Xtream live)
├── vodStream: VodStream?         (Xtream vod)
├── seriesStream: SeriesStream?   (Xtream series)
├── season: int?
└── m3uItem: M3uItem?             (M3U tüm tipler)
```

---

## 8. Video Player Entegrasyonu

### 8.1 Player Stack

| Bileşen | Kütüphane | Açıklama |
|---------|-----------|----------|
| **Video Player** | `media_kit` (libmpv backend) | Ana video çalma motoru |
| **Video UI** | `media_kit_video` | Platform-native player kontrolleri |
| **Codec/Libs** | `media_kit_libs_video` | libmpv binary'leri |
| **Audio Session** | `audio_service` + `just_audio` | OS medya oturum entegrasyonu |
| **Wakelock** | `wakelock_plus` | Ekran kapalı önleme |

### 8.2 Desteklenen Protokoller

libmpv backend sayesinde:
- **HLS** (HTTP Live Streaming) — `.m3u8`
- **MPEG-TS** (Transport Stream) — `.ts`
- **HTTP Progressive** — `.mp4`, `.mkv`, `.avi`
- **RTMP** (Real-Time Messaging Protocol)
- **DASH** (Dynamic Adaptive Streaming)
- **RTSP** (Real-Time Streaming Protocol)

### 8.3 Player Özellikleri

- **Resume/Continue watching:** `watchDuration` ile kaldığı yerden devam
- **Background playback:** `audio_service` + `MyAudioHandler` ile arka plan çalma
- **Gesture controls (mobil):** Parlaklık, ses, ileri/geri sarma
- **Long-press speed:** Uzun basmayla hızlandırma
- **Double-tap seek:** Çift dokunma ile ileri/geri atlama
- **Channel queue:** Canlı yayında yan panel kanal listesi
- **Episode queue:** Dizi izlemede bölüm listesi
- **Immersive mode:** Tam ekran (SystemChrome)
- **Desktop controls:** MaterialDesktop theme (Windows/macOS/Linux)

### 8.4 Watch History Kaydetme

- 5 saniyelik debounce ile pozisyon kaydı
- `WatchHistory` kaydı: `playlistId + streamId` (composite PK)
- `watchDuration` ve `totalDuration` millisaniye olarak saklanır
- "Continue watching" — her iki alan da dolu olan kayıtlar
- "Recently watched" — son 20 kayıt (`lastWatched` sıralı)

---

## 9. Ekranlar ve Navigasyon

### 9.1 Navigasyon Modeli

Uygulama **imperative navigation** kullanır (`Navigator.push`, `pushReplacement`, `pushAndRemoveUntil`). Router/named routes yok.

### 9.2 Ekran Haritası

```
AppInitializerScreen
├── PlaylistScreen (playlist yoksa)
│   ├── PlaylistTypeScreen
│   │   ├── NewXtreamCodePlaylistScreen → XtreamCodeDataLoaderScreen
│   │   └── NewM3uPlaylistScreen → M3uDataLoaderScreen
│   └── (playlist seçildiğinde →)
├── XtreamCodeHomeScreen (Xtream playlist için)
│   ├── Tab: Watch History → WatchHistoryScreen
│   │   └── WatchHistoryListScreen
│   ├── Tab: Live → CategoryDetailScreen → LiveStreamScreen
│   ├── Tab: Movies → CategoryDetailScreen → MovieScreen
│   ├── Tab: Series → CategoryDetailScreen → SeriesScreen
│   │   └── EpisodeScreen
│   ├── Tab: Settings → XtreamCodePlaylistSettingsScreen
│   └── SearchScreen
└── M3UHomeScreen (M3U playlist için)
    ├── Tab: History → WatchHistoryScreen
    ├── Tab: All Channels → M3uItemsScreen → M3uPlayerScreen
    ├── Tab: Settings → M3uPlaylistSettingsScreen
    └── M3uSeriesScreen → M3uEpisodeScreen
```

### 9.3 Ekran Detayları

| Ekran | Amaç | Temel Özellikler |
|-------|------|-----------------|
| **AppInitializerScreen** | Uygulama başlatma | Son playlist'i yükle, yönlendirme |
| **PlaylistScreen** | Playlist yönetimi | Liste, ekleme, silme, arama |
| **PlaylistTypeScreen** | Yeni playlist tipi seçimi | Xtream vs M3U kartları |
| **XtreamCodeHomeScreen** | Xtream ana ekranı | IndexedStack tabs, kategori rail'leri |
| **M3UHomeScreen** | M3U ana ekranı | IndexedStack tabs, responsive layout |
| **CategoryDetailScreen** | Kategori içeriği | Grid, arama, genre chip filtreleme, sıralama |
| **SearchScreen** | Xtream arama | Tab'lı arama (Live/VOD/Series) |
| **LiveStreamScreen** | Canlı yayın izleme | PlayerWidget, kanal listesi |
| **MovieScreen** | Film detay + izleme | PlayerWidget, metadata, ilgili filmler |
| **SeriesScreen** | Dizi detayı | Sezonlar, bölümler, metadata, favoriler |
| **EpisodeScreen** | Bölüm izleme | PlayerWidget, bölüm listesi |
| **WatchHistoryScreen** | İzleme geçmişi | Continue watching, recently watched, favorites |
| **M3uItemsScreen** | Tüm M3U kanalları | Arama, grup filtreleme |
| **M3uPlayerScreen** | M3U video oynatma | Tam ekran player |
| **Settings ekranları** | Ayarlar | Tema, dil, altyazı, gizli kategoriler, player tercihleri |

### 9.4 Content Navigation Router

`navigateByContentType()` utility fonksiyonu içerik tipine göre doğru ekrana yönlendirir:

```
ContentType.liveStream → LiveStreamScreen
ContentType.vod        → MovieScreen
ContentType.series     → SeriesScreen (Xtream) veya M3uSeriesScreen (M3U)
M3U items              → M3uPlayerScreen
```

---

## 10. UI Özellikleri

### 10.1 Tema Sistemi

- **Light / Dark mode** desteği — `ThemeProvider` + `SharedPreferences`
- `AppThemes` sınıfı ile `ThemeData` tanımları
- `MaterialApp`'da `theme`, `darkTheme`, `themeMode`

### 10.2 Çoklu Dil Desteği (i18n)

10 dil desteklenir:

| Kod | Dil |
|-----|-----|
| en | English |
| tr | Türkçe |
| es | Español |
| fr | Français |
| de | Deutsch |
| pt | Português |
| ru | Русский |
| hi | हिन्दी |
| ar | العربية |
| zh | 中文 |

- ARB dosyaları `lib/l10n/` altında
- `flutter gen-l10n` ile otomatik code generation
- `LocaleProvider` ile runtime dil değişimi

### 10.3 Responsive Tasarım

`ResponsiveHelper` sınıfı:
- `isDesktopOrTV` — `MediaQuery.width >= 900`
- Desktop/TV'de: Side navigation rail
- Mobil'de: Bottom navigation bar
- Grid column sayısı ekran genişliğine göre dinamik (`getCrossAxisCount`)

### 10.4 Arama ve Filtreleme

**Xtream:**
- `SearchScreen`: Live, VOD, Series tab'larında DB-level search (`LIKE '%query%'`)
- `CategoryDetailScreen`: genre ChoiceChip'leri + sıralama (A-Z, Z-A, tarih, rating)

**M3U:**
- `M3uItemsScreen`: app bar search + groupTitle bazlı filter chip'leri

### 10.5 Player Tercihleri (Settings)

| Tercih | Açıklama |
|--------|----------|
| Background play | Arka planda ses çalmaya devam |
| Brightness gesture | Kaydırma ile parlaklık |
| Volume gesture | Kaydırma ile ses |
| Seek gesture | Kaydırma ile ileri/geri |
| Long-press speed | Uzun basma ile hızlandırma |
| Double-tap seek | Çift dokunma ile atlama |
| Subtitle settings | Altyazı boyutu, renk, konum |

---

## 11. Servisler ve State Yönetimi

### 11.1 Global State (AppState)

```dart
abstract class AppState {
  static Playlist? currentPlaylist;
  static IptvRepository? xtreamCodeRepository;
  static M3uRepository? m3uRepository;
  static List<M3uItem>? m3uItems;
}
```

Playlist açıldığında set edilir, uygulama genelinde erişilir.

### 11.2 EventBus

Widget'lar arası event sistemi:
- `toggle_channel_list` — Player'da kanal listesi aç/kapat
- Diğer player-UI iletişim eventleri

### 11.3 Controller'lar Özeti

| Controller | Scope | Görev |
|-----------|-------|-------|
| `PlaylistController` | Global | Playlist CRUD, açma, arama |
| `LocaleProvider` | Global | Dil değişimi |
| `ThemeProvider` | Global | Tema değişimi |
| `IptvController` | Screen-local | Xtream veri yükleme pipeline |
| `M3uController` | Screen-local | M3U parse ve yükleme |
| `XtreamCodeHomeController` | Screen-local | Xtream home state |
| `M3UHomeController` | Screen-local | M3U home state |
| `CategoryDetailController` | Screen-local | Kategori grid, search, filter, sort |
| `LiveStreamController` | Screen-local | Canlı yayın queue yönetimi |
| `WatchHistoryController` | Screen-local | İzleme geçmişi yükleme |
| `FavoritesController` | Screen-local | Favoriler yönetimi |

---

## 12. Üçüncü Parti Bağımlılıklar

### 12.1 Temel Bağımlılıklar

| Paket | Amaç | Native Karşılığı |
|-------|------|------------------|
| `media_kit` | Video player (libmpv) | ExoPlayer (Android) / AVPlayer (iOS) |
| `drift` + `sqlite3_flutter_libs` | ORM + SQLite | Room (Android) / Core Data (iOS) / SQLite direkt |
| `provider` | State management | ViewModel (Android) / ObservableObject (iOS) |
| `get_it` | Dependency injection | Hilt/Dagger (Android) / Swinject (iOS) |
| `http` | HTTP client | OkHttp/Retrofit (Android) / URLSession (iOS) |
| `cached_network_image` | Image caching | Coil/Glide (Android) / Kingfisher (iOS) |
| `shared_preferences` | Key-value storage | SharedPreferences (Android) / UserDefaults (iOS) |
| `audio_service` + `just_audio` | Arka plan ses | MediaSession (Android) / AVAudioSession (iOS) |
| `path_provider` | Dosya yolları | Context.filesDir (Android) / FileManager (iOS) |
| `file_picker` | Dosya seçme | SAF (Android) / UIDocumentPicker (iOS) |
| `uuid` | UUID oluşturma | java.util.UUID / Foundation.UUID |
| `connectivity_plus` | Bağlantı kontrolü | ConnectivityManager / NWPathMonitor |
| `wakelock_plus` | Ekran açık tutma | WakeLock / UIApplication.isIdleTimerDisabled |
| `url_launcher` | Harici URL açma | Intent / UIApplication.open |
| `package_info_plus` | App bilgisi | PackageManager / Bundle.main |
| `flutter_in_app_pip` | PiP (kullanılmıyor) | PiP API (Android 8+) / AVPictureInPictureController |
| `rxdart` | Reactive streams | RxJava/Kotlin Flow / Combine |
| `persistent_bottom_nav_bar` | Bottom nav | BottomNavigationView / UITabBarController |
| `collection` | Koleksiyon utilities | Kotlin stdlib / Swift stdlib |

---

## 13. Native Rewrite İçin Önemli Notlar

### 13.1 Eksik/Geliştirilmesi Gereken Özellikler

1. **EPG desteği** — Şu an sadece ID saklanıyor, tam EPG çekimi ve gösterimi yok
2. **Catch-up/Timeshift** — `tvg-rec` ve `tvg-shift` parse ediliyor ama kullanılmıyor
3. **PiP** — Dependency var ama implemente edilmemiş
4. **M3U içerik tipi tespiti** — URL-based heuristic, yetersiz olabilir
5. **Favoriler listesi UI** — Placeholder SnackBar, tam liste ekranı yok
6. **M3U home category tab'ları** — Kod var ama comment-out edilmiş (live/VOD/series ayrımı)
7. **TV/Remote control** — Sadece responsive breakpoint var, tam D-pad/Leanback desteği yok
8. **Offline mode** — Cache var ama offline-first strateji yok
9. **Error recovery** — Temel try-catch var, gelişmiş retry/fallback mekanizması yok

### 13.2 Native Platform Eşleştirme Tablosu

| Flutter Katmanı | Android (Kotlin) | iOS (Swift) |
|----------------|-------------------|-------------|
| Drift (SQLite) | Room + SQLite | Core Data veya GRDB |
| Provider | ViewModel + LiveData/StateFlow | ObservableObject + @Published |
| GetIt | Hilt / Koin | Swinject / Factory |
| media_kit (libmpv) | ExoPlayer / Media3 | AVPlayer / AVKit |
| http | Retrofit + OkHttp | Alamofire / URLSession |
| cached_network_image | Coil / Glide | Kingfisher / SDWebImage |
| audio_service | MediaSessionService | AVAudioSession + MPNowPlayingInfoCenter |
| shared_preferences | DataStore / SharedPrefs | UserDefaults |
| Navigator (imperative) | Navigation Component | UINavigationController / SwiftUI NavigationStack |
| EventBus | SharedFlow / EventBus | NotificationCenter / Combine |
| flutter_lints | Detekt / ktlint | SwiftLint |

### 13.3 Kritik Tasarım Kararları

1. **Playlist scope:** Tüm veriler `playlistId` ile scope'lanır — çoklu playlist desteği temeldir
2. **Xtream vs M3U ayrımı:** Farklı data pipeline'ları, ortak `ContentItem` UI modeli
3. **Cache-first:** API verisi SQLite'a yazılır, UI DB'den okur
4. **İçerik routing:** `ContentType` enum'u ile dinamik navigasyon
5. **Composite primary keys:** Çoğu tabloda `(playlistId, streamId/categoryId)` composite PK

---

## 14. API Referans Kartı (Quick Reference)

### Xtream Codes Login
```
GET {server}/player_api.php?username={u}&password={p}
→ { user_info: {...}, server_info: {...} }
```

### Xtream Codes İçerik
```
GET {server}/player_api.php?username={u}&password={p}&action=get_live_categories
GET {server}/player_api.php?username={u}&password={p}&action=get_vod_categories
GET {server}/player_api.php?username={u}&password={p}&action=get_series_categories
GET {server}/player_api.php?username={u}&password={p}&action=get_live_streams[&category_id=X]
GET {server}/player_api.php?username={u}&password={p}&action=get_vod_streams[&category_id=X]
GET {server}/player_api.php?username={u}&password={p}&action=get_series[&category_id=X]
GET {server}/player_api.php?username={u}&password={p}&action=get_vod_info&vod_id=X
GET {server}/player_api.php?username={u}&password={p}&action=get_series_info&series_id=X
```

### Xtream Stream URL'leri
```
Live:   {server}/{username}/{password}/{stream_id}
VOD:    {server}/movie/{username}/{password}/{stream_id}.{ext}
Series: {server}/series/{username}/{password}/{episode_id}.{ext}
```

### M3U Format
```
#EXTM3U
#EXTINF:-1 tvg-id="id" tvg-name="name" tvg-logo="url" group-title="group",Display Name
http://stream-url
```

---

*Bu doküman, `/Users/ogulcanozcan/repositories/another-iptv-player` projesinin kaynak kodu analiz edilerek 5 Nisan 2026 tarihinde otomatik oluşturulmuştur.*
