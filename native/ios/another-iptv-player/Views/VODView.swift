import SwiftUI
import GRDBQuery
import GRDB

struct VODView: View {
    let playlist: Playlist
    @ObservedObject private var contentStore = PlaylistContentStore.shared
    @EnvironmentObject private var playerOverlay: PlayerOverlayController

    @State private var pendingMovieDetail: DBVODStream?

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var isSearchActive = false

    // Filtreleme sonuçları arka planda hesaplanır, main thread'e sadece atama yapılır
    @State private var displayCategories: [DBCategory] = []
    @State private var displayItemsByCategory: [String: [VODWithCategory]] = [:]

    var body: some View {
        Group {
            if displayCategories.isEmpty {
                if contentStore.isLoading || playlist.id != contentStore.activePlaylistId {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text(contentStore.loadingMessage ?? "Filmler Hazırlanıyor...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "film")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text(debouncedQuery.isEmpty ? "Hiç kategori bulunamadı." : "Arama sonucu bulunamadı.")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ScrollView {
                    ContinueWatchingRow(playlist: playlist, typeFilter: "vod") { item in
                        presentHistoryPlayer(item)
                    }

                    LazyVStack(spacing: 0) {
                        ForEach(displayCategories) { category in
                            VODCategoryShelfRow(
                                playlist: playlist,
                                category: category,
                                items: displayItemsByCategory[category.id] ?? [],
                                isStreamsLoading: !contentStore.streamsLoaded
                            )
                            .equatable()
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, isPresented: $isSearchActive, prompt: "Film Ara...")
        .onChange(of: searchText) { _, new in
            debounceTask?.cancel()
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { debouncedQuery = new }
            }
        }
        .onChange(of: isSearchActive) { _, active in
            if !active { searchText = ""; debouncedQuery = "" }
        }
        .task(id: debouncedQuery) { await recomputeFilter() }
        .task(id: contentStore.streamsLoaded) { await recomputeFilter() }
        .transaction { $0.animation = nil }
        .navigationDestination(item: $pendingMovieDetail) { movie in
            MovieDetailView(playlist: playlist, movie: movie)
        }
    }

    private func recomputeFilter() async {
        guard playlist.id == contentStore.activePlaylistId else {
            displayCategories = []; displayItemsByCategory = [:]; return
        }
        let allCats = contentStore.vodCategories
        let allByCategory = contentStore.vodStreamsByCategoryId
        let q = debouncedQuery.trimmingCharacters(in: .whitespaces)

        if q.isEmpty {
            displayCategories = allCats
            displayItemsByCategory = allByCategory
            return
        }

        // Ağır metin araması arka planda
        let result = await Task.detached(priority: .userInitiated) {
            var cats: [DBCategory] = []
            var byCategory: [String: [VODWithCategory]] = [:]
            for cat in allCats {
                let catMatch = CatalogTextSearch.matches(search: q, text: cat.name)
                let items = allByCategory[cat.id] ?? []
                let filtered = catMatch ? items : items.filter { CatalogTextSearch.matches(search: q, text: $0.stream.name) }
                if catMatch || !filtered.isEmpty {
                    cats.append(cat)
                    byCategory[cat.id] = filtered
                }
            }
            return (cats, byCategory)
        }.value

        guard !Task.isCancelled else { return }
        displayCategories = result.0
        displayItemsByCategory = result.1
    }

    private func presentHistoryPlayer(_ item: DBWatchHistory) {
        let streamIdInt = Int(item.streamId) ?? 0
        // İçerik mağazasından filmin kategorisini bul; o kategorinin tüm filmleri kuyruk olur.
        var queue: [DBVODStream] = []
        var initialMovie: DBVODStream? = nil
        for items in contentStore.vodStreamsByCategoryId.values {
            if let found = items.first(where: { $0.stream.streamId == streamIdInt }) {
                initialMovie = found.stream
                queue = items.map(\.stream)
                break
            }
        }

        if let movie = initialMovie, !queue.isEmpty {
            playerOverlay.present {
                VODPlayerShell(
                    playlist: playlist,
                    queue: queue,
                    initialMovie: movie,
                    initialResumeMs: item.lastTimeMs,
                    onNavigateToDetail: { type, id in
                        Task {
                            if type == "vod", let vId = Int(id),
                               let movie = try? await AppDatabase.shared.read({ db in
                                try DBVODStream.filter(Column("streamId") == vId && Column("playlistId") == playlist.id).fetchOne(db)
                            }) {
                                await MainActor.run {
                                    playerOverlay.dismiss()
                                    pendingMovieDetail = movie
                                }
                            }
                        }
                    }
                )
            }
            return
        }

        // Geri dönüş: içerik henüz yüklenmemişse URL ile direkt aç.
        guard let url = buildURL(for: item) else { return }
        playerOverlay.present {
            PlayerView(
                url: url,
                title: item.title,
                subtitle: item.secondaryTitle,
                artworkURL: item.imageURL.flatMap { URL(string: $0) },
                isLiveStream: false,
                playlistId: playlist.id,
                streamId: item.streamId,
                type: item.type,
                seriesId: item.seriesId,
                resumeTimeMs: item.lastTimeMs,
                containerExtension: item.containerExtension,
                onNavigateToDetail: { type, id in
                    Task {
                        if type == "vod", let vId = Int(id),
                           let movie = try? await AppDatabase.shared.read({ db in
                            try DBVODStream.filter(Column("streamId") == vId && Column("playlistId") == playlist.id).fetchOne(db)
                        }) {
                            await MainActor.run {
                                playerOverlay.dismiss()
                                pendingMovieDetail = movie
                            }
                        }
                    }
                }
            )
        }
    }

    private func buildURL(for item: DBWatchHistory) -> URL? {
        let builder = PlaybackURLBuilder(playlist: playlist)
        // VOD tab olduğu için vod varsayımı (zaten typeFilter: "vod" ile çekiyoruz)
        let streamIdInt = Int(item.streamId) ?? 0
        return builder.movieURL(streamId: streamIdInt, containerExtension: item.containerExtension)
    }
}

// MARK: - Category shelf
private enum VODCategoryShelf {
    /// İlk görünür posterler için Nuke prefetch (kaydırma `LazyHStack` + görünce yükle).
    static let prefetchHeadCount = 32
}

struct VODCategoryShelfRow: View, Equatable {
    let playlist: Playlist
    let category: DBCategory
    let items: [VODWithCategory]
    var isStreamsLoading: Bool = false

    static func == (lhs: VODCategoryShelfRow, rhs: VODCategoryShelfRow) -> Bool {
        lhs.playlist.id == rhs.playlist.id &&
        lhs.category == rhs.category &&
        lhs.items == rhs.items &&
        lhs.isStreamsLoading == rhs.isStreamsLoading
    }

    @Environment(\.posterMetrics) private var posterMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                NavigationLink {
                    VODCategoryDetailView(playlist: playlist, category: category)
                } label: {
                    HStack(spacing: 6) {
                        Text(category.name)
                            .font(.headline)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.primary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)

            if items.isEmpty {
                if isStreamsLoading {
                    Color.clear.frame(height: posterMetrics.shelfRowTotalHeight)
                } else {
                    Text("Bu kategoride film yok.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(items) { item in
                            NavigationLink {
                                MovieDetailView(playlist: playlist, movie: item.stream, queue: items.map(\.stream))
                            } label: {
                                VODStreamCard(
                                    playlistId: playlist.id,
                                    stream: item.stream,
                                    posterWidth: posterMetrics.shelfPosterWidth,
                                    posterHeight: posterMetrics.shelfPosterHeight,
                                    imageLoadProfile: .shelf
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: posterMetrics.shelfRowTotalHeight)
                .onAppear {
                    prefetchIcons(from: items)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func prefetchIcons(from list: [VODWithCategory]) {
        let urls = list.prefix(VODCategoryShelf.prefetchHeadCount)
            .compactMap { $0.stream.streamIcon }
            .compactMap { URL(string: $0) }
        ListImagePrefetch.start(urls: urls, posterMetrics: posterMetrics, isShelf: true)
    }
}

struct VODStreamCard: View {
    let stream: DBVODStream
    var categoryName: String? = nil
    var posterWidth: CGFloat = 160
    var posterHeight: CGFloat = 240
    var imageLoadProfile: ImageLoadProfile = .standard

    @Query<WatchHistoryRequest> private var watchHistory: DBWatchHistory?

    init(
        playlistId: UUID,
        stream: DBVODStream,
        categoryName: String? = nil,
        posterWidth: CGFloat = 160,
        posterHeight: CGFloat = 240,
        imageLoadProfile: ImageLoadProfile = .standard
    ) {
        self.stream = stream
        self.categoryName = categoryName
        self.posterWidth = posterWidth
        self.posterHeight = posterHeight
        self.imageLoadProfile = imageLoadProfile
        _watchHistory = Query(
            WatchHistoryRequest(streamId: String(stream.streamId), playlistId: playlistId, type: "vod"),
            in: \.appDatabase
        )
    }

    private var watchProgress: Double? {
        guard let h = watchHistory, h.durationMs > 0 else { return nil }
        return Double(h.lastTimeMs) / Double(h.durationMs)
    }

    var body: some View {
        VStack {
            ZStack(alignment: .topTrailing) {
                CachedImage(
                    url: stream.streamIcon.flatMap { URL(string: $0) },
                    width: posterWidth,
                    height: posterHeight,
                    contentMode: SwiftUI.ContentMode.fill,
                    iconName: "film",
                    loadProfile: imageLoadProfile
                )

                if let progress = watchProgress, progress > 0 {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: 4)
                        .frame(width: posterWidth * progress)
                        .frame(maxWidth: posterWidth, alignment: .leading)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(2)
                        .padding(.bottom, 2)
                        .padding(.horizontal, 4)
                }

                PosterRatingBadge(rating: stream.rating)
                    .padding(6)
            }

            Text(stream.name)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: posterWidth)
                .foregroundColor(.primary)

            if let catName = categoryName {
                Text(catName)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(width: posterWidth)
            }
        }
    }
}

// MARK: - Category Detail View
struct VODCategoryDetailView: View {
    let playlist: Playlist
    let category: DBCategory

    @ObservedObject private var contentStore = PlaylistContentStore.shared
    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var displayItems: [VODWithCategory] = []

    var body: some View {
        VODCategoryContent(playlist: playlist, items: displayItems)
            .navigationTitle(category.name)
            .navigationBarTitleDisplayMode(.large)
            .toolbar(.hidden, for: .tabBar)
            .searchable(text: $searchText, placement: .toolbar, prompt: "Film Ara...")
            .onChange(of: searchText) { _, new in
                debounceTask?.cancel()
                debounceTask = Task {
                    try? await Task.sleep(nanoseconds: 280_000_000)
                    guard !Task.isCancelled else { return }
                    await MainActor.run { debouncedQuery = new }
                }
            }
            .onDisappear { debounceTask?.cancel(); debounceTask = nil }
            .task(id: debouncedQuery) { await recomputeItems() }
            .task(id: contentStore.streamsLoaded) { await recomputeItems() }
    }

    private func recomputeItems() async {
        guard playlist.id == contentStore.activePlaylistId else { displayItems = []; return }
        let base = contentStore.vodStreamsByCategoryId[category.id] ?? []
        let q = debouncedQuery.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { displayItems = base; return }
        let result = await Task.detached(priority: .userInitiated) {
            let filtered = base.filter { CatalogTextSearch.matches(search: q, text: $0.stream.name) }
            return CatalogTextSearch.sortVODByRelevance(filtered, search: q)
        }.value
        guard !Task.isCancelled else { return }
        displayItems = result
    }
}

struct VODCategoryContent: View {
    let playlist: Playlist
    let items: [VODWithCategory]

    @Environment(\.posterMetrics) private var posterMetrics

    init(playlist: Playlist, items: [VODWithCategory]) {
        self.playlist = playlist
        self.items = items
    }

    private var categoryGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: posterMetrics.categoryGridPosterWidth), spacing: posterMetrics.gridSpacing)]
    }

    var body: some View {
        Group {
            if items.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "film")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Hiç film bulunamadı.")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: categoryGridColumns, spacing: posterMetrics.gridRowSpacing) {
                        ForEach(items) { item in
                            NavigationLink {
                                MovieDetailView(playlist: playlist, movie: item.stream, queue: items.map(\.stream))
                            } label: {
                                VODStreamCard(
                                    playlistId: playlist.id,
                                    stream: item.stream,
                                    posterWidth: posterMetrics.categoryGridPosterWidth,
                                    posterHeight: posterMetrics.categoryGridPosterHeight,
                                    imageLoadProfile: .grid
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
                .onChange(of: items) { _, newValue in
                    let urls = newValue.compactMap { $0.stream.streamIcon }.compactMap { URL(string: $0) }
                    ListImagePrefetch.start(urls: urls, posterMetrics: posterMetrics)
                }
                .onAppear {
                    let urls = items.compactMap { $0.stream.streamIcon }.compactMap { URL(string: $0) }
                    ListImagePrefetch.start(urls: urls, posterMetrics: posterMetrics)
                }
            }
        }
    }
}

// MARK: - VOD Player Shell

/// Film listesinden açılan player; kaynakla aynı kuyrukta önceki/sonraki film desteği sağlar.
struct VODPlayerShell: View {
    let playlist: Playlist
    let queue: [DBVODStream]
    var onNavigateToDetail: ((String, String) -> Void)? = nil

    @State private var currentMovie: DBVODStream
    @State private var resumeMs: Int?
    @State private var instanceId = UUID()

    init(
        playlist: Playlist,
        queue: [DBVODStream],
        initialMovie: DBVODStream,
        initialResumeMs: Int?,
        onNavigateToDetail: ((String, String) -> Void)? = nil
    ) {
        self.playlist = playlist
        self.queue = queue
        self.onNavigateToDetail = onNavigateToDetail
        _currentMovie = State(initialValue: initialMovie)
        _resumeMs = State(initialValue: initialResumeMs)
    }

    private var currentIndex: Int? {
        queue.firstIndex(where: { $0.streamId == currentMovie.streamId })
    }

    var body: some View {
        if let url = PlaybackURLBuilder(playlist: playlist).movieURL(
            streamId: currentMovie.streamId,
            containerExtension: currentMovie.containerExtension
        ) {
            let parts = [currentMovie.genre, currentMovie.releaseDate]
                .compactMap { $0 }.filter { !$0.isEmpty }
            PlayerView(
                url: url,
                title: currentMovie.name,
                subtitle: parts.isEmpty ? nil : parts.joined(separator: " · "),
                artworkURL: currentMovie.streamIcon.flatMap { URL(string: $0) },
                isLiveStream: false,
                playlistId: playlist.id,
                streamId: String(currentMovie.streamId),
                type: "vod",
                resumeTimeMs: resumeMs,
                containerExtension: currentMovie.containerExtension,
                canGoToPreviousChannel: (currentIndex ?? 0) > 0,
                canGoToNextChannel: {
                    guard let idx = currentIndex else { return false }
                    return idx < queue.count - 1
                }(),
                onPreviousChannel: { jump(by: -1) },
                onNextChannel: { jump(by: 1) },
                onNavigateToDetail: onNavigateToDetail
            )
            .id(instanceId)
        }
    }

    private func jump(by offset: Int) {
        guard let idx = currentIndex else { return }
        let newIdx = idx + offset
        guard newIdx >= 0, newIdx < queue.count else { return }
        let movie = queue[newIdx]
        Task {
            let history = try? await AppDatabase.shared.read { db in
                try DBWatchHistory
                    .filter(
                        Column("streamId") == String(movie.streamId)
                            && Column("playlistId") == playlist.id
                            && Column("type") == "vod"
                    )
                    .fetchOne(db)
            }
            var tx = Transaction()
            tx.disablesAnimations = true
            withTransaction(tx) {
                currentMovie = movie
                resumeMs = history?.lastTimeMs
                instanceId = UUID()
            }
        }
    }
}
