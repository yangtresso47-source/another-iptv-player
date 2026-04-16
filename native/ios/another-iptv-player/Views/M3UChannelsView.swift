import SwiftUI

/// Grup (group-title) başlıklı yatay raflar. Xtream Canlı TV görünümü ile aynı desen.
struct M3UChannelsView: View {
    let playlist: Playlist
    @ObservedObject private var store = M3UContentStore.shared
    @EnvironmentObject private var playerOverlay: PlayerOverlayController

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var isSearchActive = false

    /// Arama sonrası filtrelenmiş gruplar.
    @State private var displayGroups: [String] = []
    @State private var displayChannelsByGroup: [String: [DBM3UChannel]] = [:]

    /// Kategori atlama: picker sheet açık mı, ve en son talep edilen grup (scrollTo için).
    @State private var showingCategoryPicker = false
    @State private var pendingScrollTarget: String? = nil

    var body: some View {
        Group {
            if store.isLoading && store.channels.isEmpty {
                VStack(spacing: 16) {
                    ProgressView().scaleEffect(1.2)
                    Text(L("m3u.loading"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.channels.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tv.slash")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text(L("m3u.empty.no_channel"))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if displayGroups.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text(L("list.no_result"))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                shelvesList
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    M3UFavoritesView(playlist: playlist)
                } label: {
                    Image(systemName: "star.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .accessibilityLabel(L("favorites.title"))
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingCategoryPicker = true
                } label: {
                    Image(systemName: "list.bullet.indent")
                        .font(.body.weight(.semibold))
                }
                .disabled(displayGroups.isEmpty)
                .accessibilityLabel(L("list.jump_to_category"))
            }
        }
        .sheet(isPresented: $showingCategoryPicker) {
            CategoryPickerSheet(
                title: L("category_picker.title"),
                entries: displayGroups.map { g in
                    CategoryPickerSheet.Entry(
                        id: g,
                        name: g,
                        count: displayChannelsByGroup[g]?.count ?? 0
                    )
                }
            ) { id in
                showingCategoryPicker = false
                pendingScrollTarget = id
            }
        }
        .searchable(text: $searchText, isPresented: $isSearchActive, prompt: L("m3u.search_placeholder"))
        .onChange(of: searchText) { _, new in
            debounceTask?.cancel()
            // Boş aramaya geçişte debounce bekletme yok — tam listeyi anında göster.
            let trimmed = new.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                debouncedQuery = ""
                applyFull()
                return
            }
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { debouncedQuery = new }
            }
        }
        .onChange(of: isSearchActive) { _, active in
            if !active {
                debounceTask?.cancel()
                searchText = ""
                debouncedQuery = ""
                applyFull()
            }
        }
        .task(id: debouncedQuery) { await recomputeFilter() }
        .onChange(of: store.channels) { _, _ in
            // Store güncellendikçe mevcut aramayı yeniden uygula (boşsa tam liste).
            Task { await recomputeFilter() }
        }
        .onAppear { applyFull() }
    }

    /// Tam liste görüntüsüne anında dön (debounce atla).
    private func applyFull() {
        guard playlist.id == store.activePlaylistId else { return }
        displayGroups = store.groupNames
        displayChannelsByGroup = store.channelsByGroup
    }

    private var shelvesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    // İzlemeye devam: arama yokken üstte.
                    if debouncedQuery.isEmpty {
                        ContinueWatchingRow(
                            playlist: playlist,
                            destination: {
                                WatchHistoryListView(playlist: playlist, typeFilter: nil) { item in
                                    presentHistoryItem(item)
                                }
                            },
                            onPlay: { item in
                                presentHistoryItem(item)
                            }
                        )
                    }

                    ForEach(displayGroups, id: \.self) { group in
                        M3UGroupShelfRow(
                            playlist: playlist,
                            group: group,
                            items: displayChannelsByGroup[group] ?? [],
                            onChannelSelected: { channel in
                                present(channel)
                            }
                        )
                        .equatable()
                        .id(group)
                    }
                }
            }
            .onChange(of: pendingScrollTarget) { _, target in
                guard let target else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(target, anchor: .top)
                }
                // Reset; aynı grup tekrar seçilirse onChange yeniden tetiklensin.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    pendingScrollTarget = nil
                }
            }
        }
    }

    // MARK: - Filter

    private func recomputeFilter() async {
        guard playlist.id == store.activePlaylistId else {
            displayGroups = []; displayChannelsByGroup = [:]; return
        }
        let groups = store.groupNames
        let byGroup = store.channelsByGroup
        let q = debouncedQuery.trimmingCharacters(in: .whitespaces)

        if q.isEmpty {
            displayGroups = groups
            displayChannelsByGroup = byGroup
            return
        }

        let result = await Task.detached(priority: .userInitiated) {
            var outGroups: [String] = []
            var outBy: [String: [DBM3UChannel]] = [:]
            for g in groups {
                let groupMatch = CatalogTextSearch.matches(search: q, text: g)
                let items = byGroup[g] ?? []
                let filtered = groupMatch ? items : items.filter { CatalogTextSearch.matches(search: q, text: $0.name) }
                if groupMatch || !filtered.isEmpty {
                    outGroups.append(g)
                    outBy[g] = filtered
                }
            }
            return (outGroups, outBy)
        }.value

        guard !Task.isCancelled else { return }
        displayGroups = result.0
        displayChannelsByGroup = result.1
    }

    // MARK: - Playback

    private func present(_ channel: DBM3UChannel) {
        guard M3UParser.sanitizedURL(from: channel.url) != nil else { return }
        let queue = queueForChannel(channel)
        playerOverlay.present {
            M3UPlayerShell(
                playlist: playlist,
                channel: channel,
                queue: queue
            )
        }
    }

    /// Prev/next için aynı grubun kanal listesini queue olarak kullan.
    private func queueForChannel(_ channel: DBM3UChannel) -> [DBM3UChannel] {
        let key = channel.groupTitle?.trimmingCharacters(in: .whitespaces).nonEmptyOrNil
            ?? L("m3u.ungrouped_label")
        return displayChannelsByGroup[key] ?? [channel]
    }

    /// Continue Watching row'undan gelen kaydı oynatır. Kanal reimport sonrası kaybolmuşsa alert.
    private func presentHistoryItem(_ item: DBWatchHistory) {
        guard let channel = store.channels.first(where: { $0.id == item.streamId }) else {
            // Kanal silinmiş olabilir (playlist'ten kalktı). Sessizce yut, Continue row
            // bir sonraki refresh'te güncellenecek.
            return
        }
        guard M3UParser.sanitizedURL(from: channel.url) != nil else { return }
        let queue = queueForChannel(channel)
        playerOverlay.present {
            M3UPlayerShell(
                playlist: playlist,
                channel: channel,
                queue: queue,
                resumeTimeMs: item.type == "live" ? nil : item.lastTimeMs
            )
        }
    }
}

private extension String {
    var nonEmptyOrNil: String? { isEmpty ? nil : self }
}

// MARK: - Group shelf (horizontal preview)

private enum M3UShelf {
    /// Kart göründüğünde kaç sonraki logoyu önden yükleyelim.
    static let lookAhead = 10
    /// İlk açılışta kullanıcı kaydırmadan önce görünür pencere için hazırlık.
    static let initialWarmup = 6
}

struct M3UGroupShelfRow: View, Equatable {
    let playlist: Playlist
    let group: String
    let items: [DBM3UChannel]
    var onChannelSelected: ((DBM3UChannel) -> Void)? = nil

    static func == (lhs: M3UGroupShelfRow, rhs: M3UGroupShelfRow) -> Bool {
        lhs.playlist.id == rhs.playlist.id &&
        lhs.group == rhs.group &&
        lhs.items == rhs.items
    }

    @Environment(\.posterMetrics) private var posterMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                NavigationLink {
                    M3UGroupDetailView(playlist: playlist, group: group)
                } label: {
                    HStack(spacing: 6) {
                        Text(group)
                            .font(.headline)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.primary)
                }
                Spacer()
                Text("\(items.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 16)

            if items.isEmpty {
                Text(L("live.empty.no_channel_in_category"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, channel in
                            M3UChannelCard(
                                channel: channel,
                                width: posterMetrics.liveShelfLabelWidth,
                                iconSize: posterMetrics.liveShelfIcon,
                                imageLoadProfile: .shelf,
                                onChannelSelected: onChannelSelected
                            )
                            .onAppear { prefetchAhead(from: index) }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .onAppear {
                    // Sadece başlangıçta görünür pencereyi ısıt; gerisi scroll'da yüklenir.
                    prefetchAhead(from: -1, count: M3UShelf.initialWarmup)
                }
            }
        }
        .padding(.vertical, 6)
    }

    /// `index` kartı görünür olduğunda `index+1 ..< index+1+count` aralığını prefetch eder.
    /// Nuke memory cache zaten dedupe ettiği için çakışan çağrılar ucuz.
    private func prefetchAhead(from index: Int, count: Int = M3UShelf.lookAhead) {
        let start = max(0, index + 1)
        let end = min(items.count, start + count)
        guard start < end else { return }
        let urls = items[start..<end]
            .compactMap { $0.tvgLogo }
            .compactMap { URL(string: $0) }
        guard !urls.isEmpty else { return }
        ListImagePrefetch.start(urls: urls, posterMetrics: posterMetrics, isShelf: true)
    }
}

// MARK: - Channel card

struct M3UChannelCard: View {
    let channel: DBM3UChannel
    var width: CGFloat = 120
    var iconSize: CGFloat = 120
    var imageLoadProfile: ImageLoadProfile = .standard
    var onChannelSelected: ((DBM3UChannel) -> Void)? = nil

    @ObservedObject private var favorites = M3UFavoriteStore.shared

    private var isFavorite: Bool { favorites.isFavorite(channelId: channel.id) }

    var body: some View {
        Button {
            onChannelSelected?(channel)
        } label: {
            VStack(alignment: .center, spacing: 10) {
                CachedImage(
                    url: channel.tvgLogo.flatMap { URL(string: $0) },
                    width: iconSize,
                    height: iconSize,
                    cornerRadius: 12,
                    iconName: "tv",
                    loadProfile: imageLoadProfile
                )

                Text(channel.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: width)
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                Task { await favorites.toggle(channel: channel) }
            } label: {
                Label(isFavorite ? L("favorites.remove") : L("favorites.add"),
                      systemImage: isFavorite ? "star.slash" : "star")
            }
        }
    }
}

// MARK: - Group detail (grid)

struct M3UGroupDetailView: View {
    let playlist: Playlist
    let group: String

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var displayItems: [DBM3UChannel] = []

    @ObservedObject private var store = M3UContentStore.shared
    @EnvironmentObject private var playerOverlay: PlayerOverlayController

    var body: some View {
        M3UGroupGridContent(
            items: displayItems,
            onChannelSelected: { channel in
                present(channel)
            }
        )
        .navigationTitle(group)
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.hidden, for: .tabBar)
        .searchable(text: $searchText, placement: .toolbar, prompt: L("live.search_placeholder"))
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
        .task(id: store.channels.count) { await recomputeItems() }
    }

    private func recomputeItems() async {
        guard playlist.id == store.activePlaylistId else { displayItems = []; return }
        let base = store.channelsByGroup[group] ?? []
        let q = debouncedQuery.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { displayItems = base; return }
        let result = await Task.detached(priority: .userInitiated) {
            base.filter { CatalogTextSearch.matches(search: q, text: $0.name) }
        }.value
        guard !Task.isCancelled else { return }
        displayItems = result
    }

    private func present(_ channel: DBM3UChannel) {
        guard M3UParser.sanitizedURL(from: channel.url) != nil else { return }
        // Bu detay ekranında queue = bu grubun tüm kanalları (arama varsa filtrelenmiş).
        playerOverlay.present {
            M3UPlayerShell(
                playlist: playlist,
                channel: channel,
                queue: displayItems
            )
        }
    }
}

struct M3UGroupGridContent: View {
    let items: [DBM3UChannel]
    var onChannelSelected: ((DBM3UChannel) -> Void)? = nil

    @Environment(\.posterMetrics) private var posterMetrics

    /// Grid kartı göründükçe bir sonraki satır/pencereyi önden indir.
    private func prefetchAhead(from index: Int, count: Int = 16) {
        let start = max(0, index + 1)
        let end = min(items.count, start + count)
        guard start < end else { return }
        let urls = items[start..<end]
            .compactMap { $0.tvgLogo }
            .compactMap { URL(string: $0) }
        guard !urls.isEmpty else { return }
        ListImagePrefetch.start(urls: urls, posterMetrics: posterMetrics)
    }

    var body: some View {
        Group {
            if items.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text(L("list.no_channel"))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                let columns = [
                    GridItem(.adaptive(minimum: posterMetrics.liveGridIconSize),
                             spacing: posterMetrics.gridSpacing)
                ]
                ScrollView {
                    LazyVGrid(columns: columns, spacing: posterMetrics.gridRowSpacing) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, channel in
                            M3UChannelCard(
                                channel: channel,
                                width: posterMetrics.liveGridIconSize,
                                iconSize: posterMetrics.liveGridIconSize,
                                imageLoadProfile: .grid,
                                onChannelSelected: onChannelSelected
                            )
                            .onAppear { prefetchAhead(from: index) }
                        }
                    }
                    .padding()
                }
            }
        }
    }
}

// MARK: - Player shell

/// M3U oynatma — canlı kanalda önceki/sonraki kanal, VOD'da tek oynatım (prev/next gizli).
/// Queue genellikle mevcut grubun kanal listesidir; boş bırakılırsa navigation pasif.
/// `resumeTimeMs` sadece ilk kanal açılırken kullanılır (Continue Watching girişleri için).
struct M3UPlayerShell: View {
    let playlist: Playlist
    let queue: [DBM3UChannel]
    let initialResumeMs: Int?
    @State private var currentIndex: Int
    @State private var hasConsumedResume: Bool = false
    @ObservedObject private var favorites = M3UFavoriteStore.shared

    init(
        playlist: Playlist,
        channel: DBM3UChannel,
        queue: [DBM3UChannel] = [],
        resumeTimeMs: Int? = nil
    ) {
        self.playlist = playlist
        self.initialResumeMs = resumeTimeMs
        if let idx = queue.firstIndex(where: { $0.id == channel.id }) {
            self.queue = queue
            _currentIndex = State(initialValue: idx)
        } else {
            self.queue = [channel]
            _currentIndex = State(initialValue: 0)
        }
    }

    private var channel: DBM3UChannel { queue[currentIndex] }

    var body: some View {
        if let url = M3UParser.sanitizedURL(from: channel.url) {
            let classification = M3UStreamClassifier.classify(url: url, groupTitle: channel.groupTitle)
            let activeChannel = channel
            // Queue tek elemansa prev/next anlamsız; aksi hâlde live (showLiveChannelSkip) ve
            // VOD (showVODQueueSkip) için callback'leri ikisi de açık bırakılır. PlayerView
            // `type` + `isLive` kombinasyonundan hangi UI'ı göstereceğine karar veriyor.
            let hasQueueNav = queue.count > 1
            PlayerView(
                url: url,
                title: activeChannel.name,
                subtitle: activeChannel.groupTitle,
                artworkURL: activeChannel.tvgLogo.flatMap { URL(string: $0) },
                isLiveStream: classification.isLive,
                playlistId: playlist.id,
                streamId: activeChannel.id,
                type: classification.playbackType,
                resumeTimeMs: hasConsumedResume ? nil : initialResumeMs,
                containerExtension: classification.containerExtension,
                canGoToPreviousChannel: hasQueueNav && currentIndex > 0,
                canGoToNextChannel: hasQueueNav && currentIndex < queue.count - 1,
                onPreviousChannel: hasQueueNav ? { jump(offset: -1) } : nil,
                onNextChannel: hasQueueNav ? { jump(offset: 1) } : nil,
                isFavorite: favorites.isFavorite(channelId: activeChannel.id),
                onToggleFavorite: {
                    Task { await favorites.toggle(channel: activeChannel) }
                }
            )
            .id(activeChannel.id)
            .onAppear { hasConsumedResume = true }
        }
    }

    private func jump(offset: Int) {
        let target = currentIndex + offset
        guard target >= 0, target < queue.count else { return }
        currentIndex = target
    }
}

/// M3U kanallarının canlı yayın mı yoksa VOD (film/dizi) mu olduğunu tespit eder.
/// Seek bar, resume, control-center davranışları buna bağlı.
enum M3UStreamClassifier {
    struct Classification {
        /// `PlayerView.isLiveStream`'e verilir — false ise seek bar görünür, resume çalışır.
        let isLive: Bool
        /// `PlayerView.type` — watch history için ("live" | "vod").
        let playbackType: String
        /// URL'de belirgin bir dosya uzantısı varsa (mp4/mkv/...) player'a bilgi olarak iletilir.
        let containerExtension: String?
    }

    /// VOD göstergeleri: dosya uzantıları ve Xtream tarzı yollar.
    private static let vodExtensions: Set<String> = ["mp4", "mkv", "avi", "mov", "webm", "flv", "m4v", "wmv", "3gp"]
    private static let vodPathHints: [String] = ["/movie/", "/movies/", "/series/", "/vod/", "/films/", "/film/"]

    static func classify(url: URL, groupTitle: String?) -> Classification {
        let path = url.path.lowercased()
        let ext = url.pathExtension.lowercased()

        if vodPathHints.contains(where: path.contains) {
            return Classification(isLive: false, playbackType: "vod", containerExtension: ext.isEmpty ? nil : ext)
        }
        if vodExtensions.contains(ext) {
            return Classification(isLive: false, playbackType: "vod", containerExtension: ext)
        }
        // Bilinen live indikatörleri veya uzantısız Xtream-style: canlı varsay.
        return Classification(isLive: true, playbackType: "live", containerExtension: ext.isEmpty ? nil : ext)
    }
}
