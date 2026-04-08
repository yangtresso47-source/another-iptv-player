import Combine
import SwiftUI

/// Dashboard `ZStack` üzerinde tutulur; sürükleyerek kapatırken alttaki sekme içeriği görünür.
struct PlayerOverlayPresentation: Identifiable {
    let id = UUID()
    let root: AnyView
    let onDismiss: (() -> Void)?
}

final class PlayerOverlayController: ObservableObject {
    @Published var presentation: PlayerOverlayPresentation?

    func present<Content: View>(
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        presentation = PlayerOverlayPresentation(
            root: AnyView(content()),
            onDismiss: onDismiss
        )
    }

    func dismiss(animated _: Bool = true) {
        let callback = presentation?.onDismiss
        presentation = nil
        callback?()
    }
}

private struct PlayerOverlayDismissKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    /// Overlay modunda `PlayerView` kapatma; yoksa `dismiss()` kullanılır.
    var playerOverlayDismiss: (() -> Void)? {
        get { self[PlayerOverlayDismissKey.self] }
        set { self[PlayerOverlayDismissKey.self] = newValue }
    }
}
