import SwiftUI
import GRDBQuery
import GRDB

struct ContentView: View {
    @Query<PlaylistRequest> private var playlists: [Playlist]?
    
    init() {
        _playlists = Query(PlaylistRequest(), in: \.appDatabase)
    }
    @State private var showingAddPlaylist = false
    @State private var playlistToEdit: Playlist?
    @State private var offsetsToDelete: IndexSet?
    @State private var showingDeleteAlert = false
    @State private var selectedPlaylist: Playlist?
    @State private var hasAttemptedAutoLoad = false
    @Environment(\.appDatabase) private var appDatabase
    
    private let lastPlaylistKey = "lastPlaylistId"
    
    var body: some View {
        ZStack {
            if let playlist = selectedPlaylist {
                DashboardView(playlist: playlist) {
                    UserDefaults.standard.removeObject(forKey: lastPlaylistKey)
                    withAnimation(.easeInOut(duration: 0.3)) {
                        selectedPlaylist = nil
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .trailing)
                ))
            } else if let playlists = playlists {
                NavigationStack {
                    Group {
                        if playlists.isEmpty {
                            emptyState
                        } else {
                            playlistList
                        }
                    }
                    .navigationTitle("Playlists")
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                showingAddPlaylist = true
                            } label: {
                                Image(systemName: "plus")
                            }
                        }
                    }
                    .sheet(isPresented: $showingAddPlaylist) {
                        AddPlaylistView()
                    }
                    .sheet(item: $playlistToEdit) { playlist in
                        AddPlaylistView(editingPlaylist: playlist)
                    }
                    .alert("Playlist'i Sil", isPresented: $showingDeleteAlert) {
                        Button("Sil", role: .destructive) {
                            if let offsets = offsetsToDelete {
                                performDelete(offsets: offsets)
                            }
                        }
                        Button("İptal", role: .cancel) {
                            offsetsToDelete = nil
                        }
                    } message: {
                        Text("Bu playlist'i ve içindeki tüm içerikleri silmek istediğinize emin misiniz?")
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: .opacity
                ))
            } else {
                // Initial check in progress, show system background to prevent flicker
                Color(UIColor.systemBackground)
                    .ignoresSafeArea()
            }
        }
        .onAppear {
            if let playlists = playlists {
                attemptAutoLoad(playlists)
            }
        }
        .onChange(of: playlists) { _, newList in
            if let newList = newList {
                attemptAutoLoad(newList)
            }
        }
    }
    
    private func attemptAutoLoad(_ list: [Playlist]) {
        guard !hasAttemptedAutoLoad else { return }
        
        // If the query has returned (even if empty), we finalize the check
        hasAttemptedAutoLoad = true
        
        if let lastIdString = UserDefaults.standard.string(forKey: lastPlaylistKey),
           let lastId = UUID(uuidString: lastIdString),
           let playlist = list.first(where: { $0.id == lastId }) {
            selectedPlaylist = playlist
        }
    }
    
    private func selectPlaylist(_ playlist: Playlist) {
        withAnimation(.easeInOut(duration: 0.3)) {
            selectedPlaylist = playlist
            UserDefaults.standard.set(playlist.id.uuidString, forKey: lastPlaylistKey)
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "tv.badge.wifi")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .foregroundColor(.accentColor)
            
            Text("No Playlists Found")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Add your first IPTV playlist to start watching live TV, movies, and series.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            Button {
                showingAddPlaylist = true
            } label: {
                Text("Add New Playlist")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.accentColor)
                    .cornerRadius(10)
                    .padding(.horizontal, 40)
            }
            .padding(.top, 10)
        }
    }
    

    
    private var playlistList: some View {
        List {
            if let playlists = playlists {
                ForEach(playlists) { playlist in
                    Button {
                        selectPlaylist(playlist)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(playlist.name)
                                        .font(.headline)
                                    Text(playlist.serverURL)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .foregroundColor(.primary)
                    .swipeActions(edge: .leading) {
                        Button {
                            playlistToEdit = playlist
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.orange)
                    }
                }
                .onDelete(perform: deletePlaylists)
            }
        }
    }
    
    private func deletePlaylists(offsets: IndexSet) {
        offsetsToDelete = offsets
        showingDeleteAlert = true
    }
    
    private func performDelete(offsets: IndexSet) {
        Task {
            do {
                guard let playlists = playlists else { return }
                let idsToDelete = offsets.map { playlists[$0].id }
                _ = try await appDatabase.write { db in
                    try Playlist.deleteAll(db, ids: idsToDelete)
                }
            } catch {
                print("Failed to delete playlist: \(error)")
            }
            offsetsToDelete = nil
        }
    }
}

#Preview {
    ContentView()
        .environment(\.appDatabase, .empty())
}
