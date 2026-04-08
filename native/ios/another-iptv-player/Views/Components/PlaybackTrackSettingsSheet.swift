import SwiftUI

struct PlaybackTrackSettingsSheet: View {
    @ObservedObject var player: VideoPlayerController
    @Binding var showDebugOverlay: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                trackSection(
                    title: "Görüntü",
                    items: player.videoTracks,
                    currentId: player.currentVideoTrackId,
                    emptyLabel: "Görüntü parçası yok",
                    select: { player.selectVideoTrack(id: $0) }
                )
                trackSection(
                    title: "Ses",
                    items: player.audioTracks,
                    currentId: player.currentAudioTrackId,
                    emptyLabel: "Ses parçası yok",
                    select: { player.selectAudioTrack(id: $0) }
                )
                trackSection(
                    title: "Altyazı",
                    items: player.subtitleTracks,
                    currentId: player.currentSubtitleTrackId,
                    emptyLabel: "Altyazı yok",
                    select: { player.selectSubtitleTrack(id: $0) }
                )
                Section("Geliştirici") {
                    Toggle("Debug bilgilerini göster", isOn: $showDebugOverlay)
                }
            }
            .navigationTitle("Parça seçimi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
        .onAppear { player.updateTracks() }
    }

    @ViewBuilder
    private func trackSection(
        title: String,
        items: [TrackMenuOption],
        currentId: Int,
        emptyLabel: String,
        select: @escaping (Int) -> Void
    ) -> some View {
        Section(title) {
            if items.isEmpty {
                Text(emptyLabel)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    Button {
                        select(item.id)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                if let detail = item.detail, !detail.isEmpty {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            Spacer(minLength: 8)
                            if item.id == currentId {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
        }
    }
}
