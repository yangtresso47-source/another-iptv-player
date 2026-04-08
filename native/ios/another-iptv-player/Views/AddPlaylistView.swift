import SwiftUI
import GRDB

private enum PlaylistFormField: Hashable {
    case name, url, username, password
}

struct AddPlaylistView: View {
    @Environment(\.dismiss) private var dismiss
    
    let editingPlaylist: Playlist?
    
    @FocusState private var focusedField: PlaylistFormField?
    
    @State private var name: String
    @State private var url: String
    @State private var username: String
    @State private var password: String
    
    @State private var filterAdultContent: Bool

    @State private var isLoading = false
    @State private var progressMessage: String?
    @State private var errorMessage: String?
    @State private var showError = false

    init(editingPlaylist: Playlist? = nil) {
        self.editingPlaylist = editingPlaylist
        _name = State(initialValue: editingPlaylist?.name ?? "")
        _url = State(initialValue: editingPlaylist?.serverURL ?? "http://")
        _username = State(initialValue: editingPlaylist?.username ?? "")
        _password = State(initialValue: editingPlaylist?.password ?? "")
        _filterAdultContent = State(initialValue: editingPlaylist?.filterAdultContent ?? false)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Playlist Information")) {
                    TextField("Playlist Name (e.g., My IPTV)", text: $name)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .url }
                    
                    TextField("Server URL", text: $url)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($focusedField, equals: .url)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .username }
                }
                
                Section(header: Text("Credentials")) {
                    TextField("Username", text: $username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($focusedField, equals: .username)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                    
                    SecureField("Password", text: $password)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .password)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                }

                Section(header: Text("İçerik Ayarları")) {
                    Toggle(isOn: $filterAdultContent) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Yetişkin İçerikleri Filtrele")
                            Text("XXX, 18+, yetişkin kategorileri ve is_adult içerikleri gizler")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(editingPlaylist == nil ? "Add Playlist" : "Edit Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await savePlaylist() }
                    }
                    .disabled(name.isEmpty || url.isEmpty || username.isEmpty || password.isEmpty || isLoading)
                }
            }
            .overlay {
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text(progressMessage ?? "Verifying...")
                            .font(.headline)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                    .background(Color(.systemBackground).opacity(0.9))
                    .cornerRadius(12)
                    .shadow(radius: 20)
                }
            }
            .alert("Error", isPresented: $showError, actions: {
                Button("OK", role: .cancel) { }
            }, message: {
                Text(errorMessage ?? "Unknown error occurred.")
            })
        }
    }
    
    private func savePlaylist() async {
        isLoading = true
        errorMessage = nil
        progressMessage = "Doğrulanıyor..."
        
        let newPlaylist = Playlist(
            id: editingPlaylist?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            serverURL: url.trimmingCharacters(in: .whitespacesAndNewlines),
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password.trimmingCharacters(in: .whitespacesAndNewlines),
            filterAdultContent: filterAdultContent
        )

        // Credentials or filter changed check
        let detailsChanged = editingPlaylist == nil ||
            newPlaylist.serverURL != editingPlaylist?.serverURL ||
            newPlaylist.username != editingPlaylist?.username ||
            newPlaylist.password != editingPlaylist?.password ||
            newPlaylist.filterAdultContent != editingPlaylist?.filterAdultContent

        if !detailsChanged {
            // Only name changed
            do {
                try await AppDatabase.shared.write { db in
                    try newPlaylist.save(db)
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            isLoading = false
            return
        }
        
        let client = XtreamAPIClient(playlist: newPlaylist)
        
        do {
            let response = try await client.verify()

            if response.userInfo?.auth == 1 {
                await syncAndSave(newPlaylist: newPlaylist, client: client)
            } else {
                await MainActor.run {
                    errorMessage = "Authentication failed. Please check your credentials."
                    showError = true
                    isLoading = false
                    progressMessage = nil
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
                isLoading = false
                progressMessage = nil
            }
        }
    }
    
    private func syncAndSave(newPlaylist: Playlist, client: XtreamAPIClient) async {
        print("--- ADD PLAYLIST: SYNC STARTED (SQLITE) ---")
        let totalStartTime = Date()
        
        do {
            let catStart = Date()
            await MainActor.run { self.progressMessage = "Kategoriler indiriliyor..." }
            let liveCats = try await client.getLiveCategories()
            let vodCats = try await client.getVODCategories()
            let seriesCats = try await client.getSeriesCategories()
            print("NETWORK: Categories fetched in \(Date().timeIntervalSince(catStart)) seconds")
            
            let liveStart = Date()
            await MainActor.run { self.progressMessage = "Canlı yayınlar indiriliyor..." }
            let liveStreams = try await client.getLiveStreams()
            print("NETWORK: Live Streams fetched in \(Date().timeIntervalSince(liveStart)) seconds | Count: \(liveStreams.count)")
            
            let vodStart = Date()
            await MainActor.run { self.progressMessage = "Filmler indiriliyor..." }
            let vods = try await client.getVODStreams()
            print("NETWORK: VODs fetched in \(Date().timeIntervalSince(vodStart)) seconds | Count: \(vods.count)")
            
            let seriesStart = Date()
            await MainActor.run { self.progressMessage = "Diziler indiriliyor..." }
            let series = try await client.getSeries()
            print("NETWORK: Series fetched in \(Date().timeIntervalSince(seriesStart)) seconds | Count: \(series.count)")
            
            // 1. Önce Playlist'i kaydet (Böylece diğer işlemlerde hata olsa bile playlist listede görünür)
            try await AppDatabase.shared.write { db in
                try newPlaylist.save(db)
            }
            print("DATABASE: Playlist saved successfully")

            await MainActor.run { self.progressMessage = "Veritabanına kaydediliyor... Lütfen bekleyin." }
            let insertStart = Date()

            // Yetişkin içerik filtresi
            let filterAdult = newPlaylist.filterAdultContent
            let adultLiveCatIds   = filterAdult ? AdultContentFilter.adultCategoryIds(from: liveCats)   : []
            let adultVodCatIds    = filterAdult ? AdultContentFilter.adultCategoryIds(from: vodCats)    : []
            let adultSeriesCatIds = filterAdult ? AdultContentFilter.adultCategoryIds(from: seriesCats) : []

            // 2. İçerikleri Kaydet (Upsert kullanarak çakışmaları önle)
            try await AppDatabase.shared.write { db in
                // Categories
                for (index, cat) in liveCats.enumerated() {
                    if filterAdult, let name = cat.categoryName, AdultContentFilter.isAdultCategoryName(name) { continue }
                    let dbCat = DBCategory(id: cat.id, name: cat.categoryName ?? "İsimsiz", parentId: cat.parentId, type: "live", sortIndex: index, playlistId: newPlaylist.id)
                    try dbCat.save(db)
                }
                for (index, cat) in vodCats.enumerated() {
                    if filterAdult, let name = cat.categoryName, AdultContentFilter.isAdultCategoryName(name) { continue }
                    let dbCat = DBCategory(id: cat.id, name: cat.categoryName ?? "İsimsiz", parentId: cat.parentId, type: "vod", sortIndex: index, playlistId: newPlaylist.id)
                    try dbCat.save(db)
                }
                for (index, cat) in seriesCats.enumerated() {
                    if filterAdult, let name = cat.categoryName, AdultContentFilter.isAdultCategoryName(name) { continue }
                    let dbCat = DBCategory(id: cat.id, name: cat.categoryName ?? "İsimsiz", parentId: cat.parentId, type: "series", sortIndex: index, playlistId: newPlaylist.id)
                    try dbCat.save(db)
                }

                // Live Streams
                for (index, stream) in liveStreams.enumerated() {
                    if filterAdult, AdultContentFilter.isAdultLiveStream(stream, adultCategoryIds: adultLiveCatIds) { continue }
                    let dbStream = DBLiveStream(streamId: stream.id, name: stream.name ?? "İsimsiz", streamIcon: stream.streamIcon, epgChannelId: stream.epgChannelId, categoryId: stream.categoryId, sortIndex: index, playlistId: newPlaylist.id)
                    try dbStream.save(db)
                }

                // VODs
                for (index, stream) in vods.enumerated() {
                    if filterAdult, AdultContentFilter.isAdultVODStream(stream, adultCategoryIds: adultVodCatIds) { continue }
                    let dbVOD = DBVODStream(streamId: stream.id, name: stream.name ?? "İsimsiz", streamIcon: stream.streamIcon, categoryId: stream.categoryId, rating: stream.rating, containerExtension: stream.containerExtension, sortIndex: index, playlistId: newPlaylist.id)
                    try dbVOD.save(db)
                }

                // Series
                for (index, s) in series.enumerated() {
                    if filterAdult, let cid = s.categoryId, adultSeriesCatIds.contains(cid) { continue }
                    let dbSeries = DBSeries(seriesId: s.id, name: s.name ?? "İsimsiz", cover: s.cover, plot: s.plot, genre: s.genre, rating: s.rating, categoryId: s.categoryId, sortIndex: index, playlistId: newPlaylist.id)
                    try dbSeries.save(db)
                }
            }
            
            print("DATABASE: Total Insertion completed in \(Date().timeIntervalSince(insertStart)) seconds")
            print("--- TOTAL SYNC TIME: \(Date().timeIntervalSince(totalStartTime)) seconds ---")
            
            await MainActor.run {
                self.isLoading = false
                self.progressMessage = nil
                self.dismiss()
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "İçerikler indirilirken veya kaydedilirken hata oluştu: \(error.localizedDescription)"
                self.showError = true
                self.isLoading = false
                self.progressMessage = nil
            }
        }
    }
}

#Preview {
    AddPlaylistView()
}
