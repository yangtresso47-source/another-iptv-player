import SwiftUI

struct PlaybackTrackSettingsSheet: View {
    @ObservedObject var player: VideoPlayerController
    @Binding var showDebugOverlay: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                trackSection(
                    title: L("player.tracks.video"),
                    items: player.videoTracks,
                    currentId: player.currentVideoTrackId,
                    emptyLabel: L("player.tracks.empty.video"),
                    select: { player.selectVideoTrack(id: $0) }
                )
                trackSection(
                    title: L("player.tracks.audio"),
                    items: player.audioTracks,
                    currentId: player.currentAudioTrackId,
                    emptyLabel: L("player.tracks.empty.audio"),
                    select: { player.selectAudioTrack(id: $0) }
                )
                trackSection(
                    title: L("player.tracks.subtitle"),
                    items: player.subtitleTracks,
                    currentId: player.currentSubtitleTrackId,
                    emptyLabel: L("player.tracks.empty.subtitle"),
                    select: { player.selectSubtitleTrack(id: $0) }
                )
                Section(L("player.dev_section")) {
                    Toggle(L("player.show_debug_overlay"), isOn: $showDebugOverlay)
                }
            }
            .navigationTitle(L("player.tracks.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common.close")) { dismiss() }
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
