import SwiftUI

class AppDelegate: NSObject, UIApplicationDelegate {
    /// Varsayılan: tüm yönler. `LiveChannelBrowserScreen` açıkken `.landscape` yapılır.
    static var orientationLock: UIInterfaceOrientationMask = .allButUpsideDown

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }
}

@main
struct another_iptv_playerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        IPTVRemoteImagePipeline.installAsShared()
        _ = AppDatabase.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.appDatabase, .shared)
        }
    }
}
