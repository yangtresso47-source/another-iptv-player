import SwiftUI

struct DashboardView: View {
    let playlist: Playlist
    let onDismiss: () -> Void
    @ObservedObject private var contentStore = PlaylistContentStore.shared
    @StateObject private var playerOverlay = PlayerOverlayController()

    /// 0 = Canlı TV … 4 = Arama (Ana Sayfa sekmesi kaldırıldı; eski kayıtlı indeksler tek sefer taşınır).
    @AppStorage("dashboard_selected_tab") private var savedTab: Int = 0
    @State private var selectedTab: Int = 0
    @AppStorage("dashboard_removed_home_tab_migration_v1") private var didMigrateTabIndicesAfterHomeRemoval = false

    @State private var globalSearchText: String = ""

    /// Ayarlar (3) ve Arama (4) seçildiğinde AppStorage'a yazmaz.
    private var tabBinding: Binding<Int> {
        Binding(
            get: { selectedTab },
            set: { newTab in
                selectedTab = newTab
                if newTab < 3 { savedTab = newTab }
            }
        )
    }

    @State private var windowSize = UIScreen.main.bounds.size

    var body: some View {
        ZStack {
            TabView(selection: tabBinding) {
                Tab("Canlı TV", systemImage: "tv", value: 0) {
                    NavigationStack {
                        LiveStreamsView(playlist: playlist)
                            .dashboardNavigation(playlist: playlist, tabTitle: "Canlı TV", type: "live", onDismiss: onDismiss)
                    }
                }

                Tab("Filmler", systemImage: "film", value: 1) {
                    NavigationStack {
                        VODView(playlist: playlist)
                            .dashboardNavigation(playlist: playlist, tabTitle: "Filmler", type: "vod", onDismiss: onDismiss)
                    }
                }

                Tab("Diziler", systemImage: "play.tv", value: 2) {
                    NavigationStack {
                        SeriesView(playlist: playlist)
                            .dashboardNavigation(playlist: playlist, tabTitle: "Diziler", type: "series", onDismiss: onDismiss)
                    }
                }

                Tab("Ayarlar", systemImage: "gear", value: 3) {
                    NavigationStack {
                        PlaylistSettingsView(playlist: playlist, onDismiss: onDismiss)
                            .dashboardNavigation(playlist: playlist, tabTitle: "Ayarlar", onDismiss: onDismiss)
                    }
                }

                Tab(value: 4, role: .search) {
                    NavigationStack {
                        SearchView(playlist: playlist, searchText: $globalSearchText)
                            .navigationTitle("Arama")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                }
            }
            .tabViewStyle(.sidebarAdaptable)
            .searchable(text: $globalSearchText, prompt: "Kanal, Film veya Dizi Ara...")
            .environment(\.posterMetrics, PosterMetrics(windowSize: windowSize))

            ZStack {
                if let item = playerOverlay.presentation {
                    item.root
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .environment(\.playerOverlayDismiss) {
                            playerOverlay.dismiss(animated: true)
                        }
                        .transition(.move(edge: .bottom))
                }
            }
            .animation(.easeOut(duration: 0.22), value: playerOverlay.presentation?.id)
            .zIndex(10_000)
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { windowSize = geo.size }
                    .onChange(of: geo.size) { _, size in windowSize = size }
            }
        )
        .environmentObject(playerOverlay)
        .task {
            if !didMigrateTabIndicesAfterHomeRemoval {
                if savedTab != 0 {
                    savedTab -= 1
                }
                didMigrateTabIndicesAfterHomeRemoval = true
            }
            selectedTab = savedTab
        }
        .task(id: playlist.id) {
            await contentStore.loadPlaylist(playlist)
        }
        .alert("Yükleme hatası", isPresented: Binding(
            get: {
                contentStore.loadError != nil
                    && contentStore.activePlaylistId == playlist.id
                    && !contentStore.isLoading
            },
            set: { if !$0 { contentStore.loadError = nil } }
        )) {
            Button("Tamam") {
                contentStore.loadError = nil
            }
            Button("Tekrar dene") {
                contentStore.loadError = nil
                Task { await contentStore.loadPlaylist(playlist) }
            }
        } message: {
            Text(contentStore.loadError ?? "")
        }
    }


}

// MARK: - Dashboard Navigation Modifier
private struct DashboardNavigationModifier: ViewModifier {
    let playlist: Playlist
    let tabTitle: String
    let type: String?
    let onDismiss: () -> Void
    @Environment(\.posterMetrics) private var posterMetrics

    func body(content: Content) -> some View {
        content
            .navigationTitle(tabTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if let type = type {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        NavigationLink(destination: FavoritesView(playlist: playlist, initialType: type)) {
                            Image(systemName: "star.fill")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
            .toolbar(.visible, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

extension View {
    func dashboardNavigation(playlist: Playlist, tabTitle: String, type: String? = nil, onDismiss: @escaping () -> Void) -> some View {
        modifier(DashboardNavigationModifier(playlist: playlist, tabTitle: tabTitle, type: type, onDismiss: onDismiss))
    }
}
