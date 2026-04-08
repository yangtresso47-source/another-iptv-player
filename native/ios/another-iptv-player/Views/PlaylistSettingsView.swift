import SwiftUI
import GRDB

struct PlaylistSettingsView: View {
    let playlist: Playlist
    let onDismiss: () -> Void
    
    @State private var authResponse: XtreamAuthResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    @State private var isPasswordRevealed = false
    
    @State private var isSyncing = false
    @State private var progressMessage: String?
    
    @State private var liveCount: Int = 0
    @State private var vodCount: Int = 0
    @State private var seriesCount: Int = 0
    @State private var historyCount: Int = 0
    
    @State private var filterAdultContent: Bool
    @State private var showClearHistoryAlert = false
    
    init(playlist: Playlist, onDismiss: @escaping () -> Void) {
        self.playlist = playlist
        self.onDismiss = onDismiss
        _filterAdultContent = State(initialValue: playlist.filterAdultContent)
    }

    var body: some View {
        Form {
            Section(header: Text("Playlist Bilgileri")) {
                HStack {
                    Text("İsim")
                    Spacer()
                    Text(playlist.name)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Sunucu URL")
                    Spacer()
                    Text(playlist.serverURL)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Kullanıcı Adı")
                    Spacer()
                    Text(playlist.username)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Şifre")
                    Spacer()
                    if isPasswordRevealed {
                        Text(playlist.password)
                            .foregroundColor(.secondary)
                    } else {
                        Text(String(repeating: "•", count: playlist.password.count))
                            .foregroundColor(.secondary)
                    }
                    
                    Button(action: {
                        isPasswordRevealed.toggle()
                    }) {
                        Image(systemName: isPasswordRevealed ? "eye.slash" : "eye")
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
            }
            
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView("Abonelik Bilgileri Yükleniyor...")
                    Spacer()
                }
            } else if let error = errorMessage {
                Section {
                    Text("Bilgiler alınamadı: \(error)")
                        .foregroundColor(.red)
                    Button("Tekrar Dene") {
                        Task { await fetchAuthInfo() }
                    }
                }
            } else if let userInfo = authResponse?.userInfo {
                Section(header: HStack {
                    Text("Abonelik Bilgileri")
                    Spacer()
                    Button(action: {
                        Task { await fetchAuthInfo() }
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .textCase(.none)
                }) {
                    HStack {
                        Text("Kalan Süre")
                        Spacer()
                        Text(calculateRemainingDays(expDate: userInfo.expDate))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Aktif Bağlantı")
                        Spacer()
                        Text(userInfo.activeCons ?? "Bilinmiyor")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Maksimum Bağlantı")
                        Spacer()
                        Text(userInfo.maxConnections ?? "Sınırsız")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Sunucu Bilgileri")) {
                    if let timeZone = authResponse?.serverInfo?.timezone {
                        HStack {
                            Text("Time Zone")
                            Spacer()
                            Text(timeZone)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let message = userInfo.message, !message.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Server Message")
                            Text(message)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section(header: Text("İçerik İstatistikleri")) {
                    HStack {
                        Text("Canlı Yayın Sayısı")
                        Spacer()
                        Text("\(liveCount)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Film Sayısı")
                        Spacer()
                        Text("\(vodCount)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Dizi Sayısı")
                        Spacer()
                        Text("\(seriesCount)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("İzleme Geçmişi")
                        Spacer()
                        Text("\(historyCount) öğe")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("İçerik Yönetimi")) {
                    Toggle(isOn: $filterAdultContent) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Yetişkin İçerikleri Filtrele")
                            Text("Değişiklik sonrası içeriklerin yeniden indirilmesi gerekir")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: filterAdultContent) { _, newValue in
                        Task { await saveFilterSetting(newValue: newValue) }
                    }

                    Button(action: {
                        Task { await syncContents() }
                    }) {
                        HStack {
                            Text("Tüm İçerikleri Yeniden İndir")
                            Spacer()
                            if isSyncing {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isSyncing)

                    if isSyncing, let msg = progressMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Button(role: .destructive) {
                        showClearHistoryAlert = true
                    } label: {
                        HStack {
                            Text("İzleme Geçmişini Temizle")
                            Spacer()
                            Image(systemName: "trash")
                        }
                    }
                    .disabled(historyCount == 0)
                }
                
                Section(header: Text("Sistem")) {
                    Button {
                        onDismiss()
                    } label: {
                        HStack {
                            Text("Playlist Listesine Dön")
                            Spacer()
                            Image(systemName: "list.bullet.rectangle")
                        }
                    }
                }
            }
        }
        .alert("Geçmişi Sil", isPresented: $showClearHistoryAlert) {
            Button("İptal", role: .cancel) { }
            Button("Evet, Sil", role: .destructive) {
                Task { await clearHistory() }
            }
        } message: {
            Text("Tüm izleme geçmişiniz (devam et, son izlenenler) kalıcı olarak silinecektir. Emin misiniz?")
        }
        .task {
            await fetchAuthInfo()
            await fetchLocalStats()
        }
        .refreshable {
            await fetchAuthInfo()
            await fetchLocalStats()
        }
    }
    
    private func fetchLocalStats() async {
        do {
            let pid = playlist.id
            let counts = try await AppDatabase.shared.read { db in
                let live = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM liveStream WHERE playlistId = ?", arguments: [pid]) ?? 0
                let vod = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM vodStream WHERE playlistId = ?", arguments: [pid]) ?? 0
                let series = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM series WHERE playlistId = ?", arguments: [pid]) ?? 0
                let history = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM watchHistory WHERE playlistId = ?", arguments: [pid]) ?? 0
                return (live, vod, series, history)
            }
            
            await MainActor.run {
                self.liveCount = counts.0
                self.vodCount = counts.1
                self.seriesCount = counts.2
                self.historyCount = counts.3
            }
        } catch {
            print("Stats fetch error: \(error)")
        }
    }
    
    private func clearHistory() async {
        do {
            let pid = playlist.id
            try await AppDatabase.shared.write { db in
                try db.execute(sql: "DELETE FROM watchHistory WHERE playlistId = ?", arguments: [pid])
            }
            await fetchLocalStats()
            // Continue watching row in Dashboard will update via GRDB watcher if implemented,
            // or on next disappear/appear.
        } catch {
            print("History clear error: \(error)")
        }
    }
    
    private func fetchAuthInfo() async {
        isLoading = true
        errorMessage = nil
        let client = XtreamAPIClient(playlist: playlist)
        do {
            let response = try await client.verify()
            await MainActor.run {
                self.authResponse = response
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    private func calculateRemainingDays(expDate: String?) -> String {
        guard let expDateStr = expDate, let timestamp = TimeInterval(expDateStr) else {
            return "Sınırsız / Bilinmiyor"
        }
        
        if timestamp == 0 {
            return "Sınırsız"
        }
        
        let displayDate = Date(timeIntervalSince1970: timestamp)
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: displayDate)
        
        if let days = components.day {
            if days < 0 {
                return "Süresi Dolmuş"
            }
            return "\(days) Gün"
        }
        return "Bilinmiyor"
    }
    
    private func saveFilterSetting(newValue: Bool) async {
        var updated = playlist
        updated.filterAdultContent = newValue
        do {
            try await AppDatabase.shared.write { db in
                try updated.save(db)
            }
            // Filtre değişince içerikleri otomatik yeniden indir
            await syncContents()
        } catch {
            await MainActor.run {
                self.errorMessage = "Ayar kaydedilemedi: \(error.localizedDescription)"
            }
        }
    }

    private func syncContents() async {
        isSyncing = true
        errorMessage = nil
        print("--- REFRESH SETTINGS: SYNC STARTED (SQLITE) ---")
        let totalStartTime = Date()

        do {
            try await PlaylistContentStore.shared.syncFromNetworkReplacingLocal(playlist: playlist) { msg in
                progressMessage = msg
            }
            print("--- REFRESH TOTAL TIME: \(Date().timeIntervalSince(totalStartTime)) seconds ---")
            await fetchLocalStats()
            await PlaylistContentStore.shared.reloadFromDatabaseIfActive(playlistId: playlist.id)
            await MainActor.run {
                self.isSyncing = false
                self.progressMessage = nil
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "İçerikler yenilenirken hata oluştu: \(error.localizedDescription)"
                self.isSyncing = false
                self.progressMessage = nil
            }
        }
    }
}

