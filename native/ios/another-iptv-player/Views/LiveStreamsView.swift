import SwiftUI
import GRDBQuery

struct LiveStreamsView: View {
    let playlist: Playlist
    @ObservedObject private var contentStore = PlaylistContentStore.shared
    @EnvironmentObject private var playerOverlay: PlayerOverlayController

    @State private var showLiveChannelBrowser = false
    /// Tarayıcı kapanırken seçilen kanal; `onDismiss` içinde `presentLiveSelection` ile overlay açılır.
    @State private var pendingStreamAfterBrowserDismiss: DBLiveStream?

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var isSearchActive = false

    @State private var displayCategories: [DBCategory] = []
    @State private var displayItemsByCategory: [String: [LiveStreamWithCategory]] = [:]

    private var livePlaybackQueue: [DBLiveStream] {
        displayCategories.flatMap { displayItemsByCategory[$0.id]?.map(\.stream) ?? [] }
    }

    private var liveChannelSections: [LiveChannelCategorySection] {
        displayCategories.compactMap { cat in
            let streams = displayItemsByCategory[cat.id]?.map(\.stream) ?? []
            guard !streams.isEmpty else { return nil }
            return LiveChannelCategorySection(id: cat.id, title: cat.name, streams: streams)
        }
    }

    private func liveQueueIndex(for stream: DBLiveStream) -> Int? {
        livePlaybackQueue.firstIndex(where: { $0.streamId == stream.streamId })
    }

    var body: some View {
        Group {
            if displayCategories.isEmpty {
                if contentStore.isLoading || playlist.id != contentStore.activePlaylistId {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text(contentStore.loadingMessage ?? "Kanallar Hazırlanıyor...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "tv.slash")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text(debouncedQuery.isEmpty ? "Hiç kategori bulunamadı." : "Arama sonucu bulunamadı.")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                contentList
            }
        }
        .searchable(text: $searchText, isPresented: $isSearchActive, prompt: "Kanal Ara...")
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
        .fullScreenCover(isPresented: $showLiveChannelBrowser, onDismiss: {
            guard let stream = pendingStreamAfterBrowserDismiss else { return }
            pendingStreamAfterBrowserDismiss = nil
            DispatchQueue.main.async {
                presentLiveSelection(LivePlayerSelection(stream: stream, history: nil))
            }
        }) {
            NavigationStack {
                LiveChannelBrowserScreen(
                    sections: liveChannelSections,
                    currentStreamId: nil,
                    onSelectChannel: { stream in
                        pendingStreamAfterBrowserDismiss = stream
                        showLiveChannelBrowser = false
                    }
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showLiveChannelBrowser = true
                } label: {
                    Image(systemName: "rectangle.split.3x1")
                        .font(.body.weight(.semibold))
                }
                .disabled(liveChannelSections.isEmpty)
                .accessibilityLabel("Kanal listesi")
            }
        }
    }

    private func presentLiveSelection(_ selection: LivePlayerSelection) {
        playerOverlay.present {
            LivePlayerShell(
                playlist: playlist,
                queue: livePlaybackQueue,
                sections: liveChannelSections,
                initialStream: selection.stream,
                initialHistory: selection.history,
                subtitle: nil
            )
        }
    }

    private func presentHistoryItem(_ item: DBWatchHistory) {
        guard let url = historyURL(for: item) else { return }
        if item.type == "series" {
            playerOverlay.present {
                HistorySeriesPlayerShell(playlist: playlist, history: item, url: url)
            }
        } else if item.type == "live" {
            let stream = liveStream(for: item) ?? DBLiveStream(
                streamId: Int(item.streamId) ?? 0,
                name: item.title,
                streamIcon: item.imageURL,
                categoryId: nil,
                sortIndex: 0,
                playlistId: item.playlistId
            )
            playerOverlay.present {
                LivePlayerShell(
                    playlist: playlist,
                    queue: livePlaybackQueue,
                    sections: liveChannelSections,
                    initialStream: stream,
                    initialHistory: item,
                    subtitle: nil
                )
            }
        } else {
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
                    resumeTimeMs: item.lastTimeMs
                )
            }
        }
    }

    private var contentList: some View {
        ScrollView {
            ContinueWatchingRow(playlist: playlist, typeFilter: "live") { item in
                presentHistoryItem(item)
            }
            
            LazyVStack(spacing: 0) {
                ForEach(displayCategories) { category in
                    LiveCategoryShelfRow(
                        playlist: playlist,
                        category: category,
                        items: displayItemsByCategory[category.id] ?? [],
                        onStreamSelected: { stream, history in
                            presentLiveSelection(LivePlayerSelection(stream: stream, history: history))
                        },
                        isStreamsLoading: !contentStore.streamsLoaded
                    )
                    .equatable()
                }
            }
        }
    }

    private func historyURL(for item: DBWatchHistory) -> URL? {
        let builder = PlaybackURLBuilder(playlist: playlist)
        switch item.type {
        case "live":
            return builder.liveURL(streamId: Int(item.streamId) ?? 0)
        case "vod":
            // MovieDetailView stores streamId as string, builder needs int
            return builder.movieURL(streamId: Int(item.streamId) ?? 0, containerExtension: nil)
        case "series":
            // EpisodeId might be an integer or string in different IPTV setups
            return builder.seriesURL(streamId: item.streamId, containerExtension: nil)
        default:
            return nil
        }
    }

    private func recomputeFilter() async {
        guard playlist.id == contentStore.activePlaylistId else {
            displayCategories = []; displayItemsByCategory = [:]; return
        }
        let allCats = contentStore.liveCategories
        let allByCategory = contentStore.liveStreamsByCategoryId
        let q = debouncedQuery.trimmingCharacters(in: .whitespaces)

        if q.isEmpty {
            displayCategories = allCats
            displayItemsByCategory = allByCategory
            return
        }

        let result = await Task.detached(priority: .userInitiated) {
            var cats: [DBCategory] = []
            var byCategory: [String: [LiveStreamWithCategory]] = [:]
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

    private func liveStream(for item: DBWatchHistory) -> DBLiveStream? {
        let streamId = Int(item.streamId) ?? 0
        if let match = livePlaybackQueue.first(where: { $0.streamId == streamId }) {
            return match
        }
        return contentStore.liveStreamsByCategoryId.values
            .flatMap { $0 }
            .map(\.stream)
            .first(where: { $0.streamId == streamId })
    }
}

// MARK: - Category shelf (horizontal preview)
private enum CategoryShelf {
    static let prefetchHeadCount = 32
}

struct LiveCategoryShelfRow: View, Equatable {
    let playlist: Playlist
    let category: DBCategory
    let items: [LiveStreamWithCategory]
    var onStreamSelected: ((DBLiveStream, DBWatchHistory?) -> Void)? = nil
    var isStreamsLoading: Bool = false

    static func == (lhs: LiveCategoryShelfRow, rhs: LiveCategoryShelfRow) -> Bool {
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
                    LiveCategoryDetailView(playlist: playlist, category: category)
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
                    Color.clear.frame(height: posterMetrics.liveShelfIcon + 30)
                } else {
                    Text("Bu kategoride kanal yok.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(items) { item in
                            LiveStreamCard(
                                playlistId: playlist.id,
                                stream: item.stream,
                                width: posterMetrics.liveShelfLabelWidth,
                                iconSize: posterMetrics.liveShelfIcon,
                                imageLoadProfile: .shelf
                            ) { stream, history in
                                onStreamSelected?(stream, history)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .onAppear {
                    prefetchIcons(from: items)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func prefetchIcons(from list: [LiveStreamWithCategory]) {
        let urls = list.prefix(CategoryShelf.prefetchHeadCount)
            .compactMap { $0.stream.streamIcon }
            .compactMap { URL(string: $0) }
        ListImagePrefetch.start(urls: urls, posterMetrics: posterMetrics, isShelf: true)
    }
}

struct LiveStreamCard: View {
    let playlistId: UUID
    let stream: DBLiveStream
    var width: CGFloat = 120
    var iconSize: CGFloat = 120
    var imageLoadProfile: ImageLoadProfile = .standard
    var onStreamSelected: ((DBLiveStream, DBWatchHistory?) -> Void)? = nil

    var body: some View {
        Button(action: {
            onStreamSelected?(stream, nil)
        }) {
            VStack(alignment: .center, spacing: 10) {
                CachedImage(
                    url: stream.streamIcon.flatMap { URL(string: $0) },
                    width: iconSize,
                    height: iconSize,
                    cornerRadius: 12,
                    iconName: "tv",
                    loadProfile: imageLoadProfile
                )

                Text(stream.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: width)
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Category Detail View
struct LiveCategoryDetailView: View {
    let playlist: Playlist
    let category: DBCategory

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var displayItems: [LiveStreamWithCategory] = []

    @ObservedObject private var contentStore = PlaylistContentStore.shared
    @EnvironmentObject private var playerOverlay: PlayerOverlayController

    private var currentStreams: [DBLiveStream] { displayItems.map(\.stream) }

    var body: some View {
        LiveCategoryContent(
            playlist: playlist,
            items: displayItems,
            onStreamSelected: { stream, history in
                let selection = LivePlayerSelection(stream: stream, history: history)
                playerOverlay.present {
                    LivePlayerShell(
                        playlist: playlist,
                        queue: currentStreams,
                        sections: [LiveChannelCategorySection(id: category.id, title: category.name, streams: currentStreams)],
                        initialStream: selection.stream,
                        initialHistory: selection.history,
                        subtitle: category.name
                    )
                }
            }
        )
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.hidden, for: .tabBar)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Kanal Ara...")
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
        let base = contentStore.liveStreamsByCategoryId[category.id] ?? []
        let q = debouncedQuery.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { displayItems = base; return }
        let result = await Task.detached(priority: .userInitiated) {
            let filtered = base.filter { CatalogTextSearch.matches(search: q, text: $0.stream.name) }
            return CatalogTextSearch.sortLiveByRelevance(filtered, search: q)
        }.value
        guard !Task.isCancelled else { return }
        displayItems = result
    }
}

struct LiveCategoryContent: View {
    let playlist: Playlist
    let items: [LiveStreamWithCategory]
    var onStreamSelected: ((DBLiveStream, DBWatchHistory?) -> Void)? = nil

    @Environment(\.posterMetrics) private var posterMetrics

    var body: some View {
        Group {
            if items.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Hiç kanal bulunamadı.")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                let columns = [
                    GridItem(.adaptive(minimum: posterMetrics.liveGridIconSize), spacing: posterMetrics.gridSpacing)
                ]
                ScrollView {
                    LazyVGrid(columns: columns, spacing: posterMetrics.gridRowSpacing) {
                        ForEach(items) { item in
                            LiveStreamCard(
                                playlistId: playlist.id,
                                stream: item.stream,
                                width: posterMetrics.liveGridIconSize,
                                iconSize: posterMetrics.liveGridIconSize,
                                imageLoadProfile: .grid,
                                onStreamSelected: onStreamSelected
                            )
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

struct LivePlayerSelection: Identifiable {
    let id = UUID()
    let stream: DBLiveStream
    let history: DBWatchHistory?
}

struct LivePlayerShell: View {
    let playlist: Playlist
    let queue: [DBLiveStream]
    let sections: [LiveChannelCategorySection]
    let subtitle: String?

    @State private var session: LivePlaybackSession

    init(
        playlist: Playlist,
        queue: [DBLiveStream],
        sections: [LiveChannelCategorySection],
        initialStream: DBLiveStream,
        initialHistory: DBWatchHistory?,
        subtitle: String?
    ) {
        self.playlist = playlist
        self.queue = queue
        self.sections = sections
        self.subtitle = subtitle
        let initialURL = PlaybackURLBuilder(playlist: playlist).liveURL(streamId: initialStream.streamId)
        _session = State(initialValue: LivePlaybackSession(
            stream: initialStream,
            url: initialURL,
            resumeTimeMs: initialHistory?.lastTimeMs,
            instanceId: UUID()
        ))
    }

    private var currentIndex: Int? {
        queue.firstIndex(where: { $0.streamId == session.stream.streamId })
    }

    var body: some View {
        if let url = session.url {
            PlayerView(
                url: url,
                title: session.stream.name,
                subtitle: subtitle,
                artworkURL: session.stream.streamIcon.flatMap { URL(string: $0) },
                isLiveStream: true,
                playlistId: playlist.id,
                streamId: String(session.stream.streamId),
                type: "live",
                resumeTimeMs: session.resumeTimeMs,
                canGoToPreviousChannel: (currentIndex ?? 0) > 0,
                canGoToNextChannel: {
                    guard let index = currentIndex else { return false }
                    return index < queue.count - 1
                }(),
                onPreviousChannel: { jump(offset: -1) },
                onNextChannel: { jump(offset: 1) },
                liveChannelQueue: queue,
                liveChannelSections: sections,
                currentLiveChannelStreamId: session.stream.streamId,
                onSelectLiveChannel: { stream in
                    switchTo(stream: stream, resumeTimeMs: nil)
                }
            )
            .id(session.instanceId)
        }
    }

    private func jump(offset: Int) {
        guard let index = currentIndex else { return }
        let target = index + offset
        guard target >= 0, target < queue.count else { return }
        let targetStream = queue[target]
        switchTo(stream: targetStream, resumeTimeMs: nil)
    }

    private func switchTo(stream: DBLiveStream, resumeTimeMs: Int?) {
        let targetURL = PlaybackURLBuilder(playlist: playlist).liveURL(streamId: stream.streamId)
        if session.stream.streamId == stream.streamId, session.url == targetURL {
            return
        }
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            session = LivePlaybackSession(
                stream: stream,
                url: targetURL,
                resumeTimeMs: resumeTimeMs,
                // Kanal değişiminde yeni PlayerView/VideoPlayerController/MPVPlayer zinciri oluştur.
                instanceId: UUID()
            )
        }
    }
}

struct LivePlaybackSession: Equatable {
    var stream: DBLiveStream
    var url: URL?
    var resumeTimeMs: Int?
    /// Her kanal geçişinde yeni `PlayerView` / `VideoPlayerController` örneği için SwiftUI kimliği.
    var instanceId: UUID
}
