import SwiftUI
import CloudKit

@main
struct HappyMamaApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #else
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    private let env = AppEnvironment.shared

    init() {
        env.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, env.persistence.viewContext)
                .environmentObject(env.identity)
                .environmentObject(env.service)
                .environmentObject(PersistenceBox(env.persistence))
                .tint(Theme.accent)
                #if os(macOS)
                .frame(minWidth: 860, minHeight: 580)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 980, height: 680)
        #endif
    }
}

/// Lets views reach the persistence layer (for sharing) through the environment.
final class PersistenceBox: ObservableObject {
    let persistence: PersistenceController
    init(_ persistence: PersistenceController) { self.persistence = persistence }
}

#if os(iOS)
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        AppEnvironment.shared.start()
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

/// Receives the invitation when someone taps a Happy Mama share link.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            AppEnvironment.shared.persistence.accept(metadata)
        }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        AppEnvironment.shared.persistence.accept(cloudKitShareMetadata)
    }
}
#else
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppEnvironment.shared.start()
        NSApplication.shared.registerForRemoteNotifications()
    }

    func application(_ application: NSApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        AppEnvironment.shared.persistence.accept(metadata)
    }
}
#endif
