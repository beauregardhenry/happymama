import SwiftUI
import CloudKit

struct SharePayload: Identifiable {
    let id = UUID()
    let share: CKShare
    let container: CKContainer
}

/// "Invite someone" — opens the system iCloud sharing sheet for the household.
struct InviteButton: View {
    let household: Household
    @EnvironmentObject private var box: PersistenceBox
    @State private var payload: SharePayload?
    @State private var working = false
    @State private var error: String?

    var body: some View {
        Button { Task { await prepare() } } label: {
            Label(working ? "Preparing…" : "Invite Someone…", systemImage: "person.badge.plus")
        }
        .disabled(working)
        #if os(iOS)
        .sheet(item: $payload) { payload in
            CloudSharingView(payload: payload, title: "Join \(household.displayName) on Happy Mama")
                .ignoresSafeArea()
        }
        #endif
        .errorAlert($error)
    }

    private func prepare() async {
        working = true
        defer { working = false }
        do {
            let (share, container) = try await box.persistence.share(household)
            let payload = SharePayload(share: share, container: container)
            #if os(iOS)
            self.payload = payload
            #else
            MacSharing.shared.present(payload)
            #endif
        } catch {
            self.error = error.localizedDescription
        }
    }
}

#if os(iOS)
import UIKit

struct CloudSharingView: UIViewControllerRepresentable {
    let payload: SharePayload
    let title: String

    func makeCoordinator() -> Coordinator { Coordinator(title: title) }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: payload.share, container: payload.container)
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let title: String
        init(title: String) { self.title = title }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {}
        func itemTitle(for csc: UICloudSharingController) -> String? { title }
    }
}
#else
import AppKit

/// Presents the macOS iCloud sharing picker.
final class MacSharing: NSObject, NSCloudSharingServiceDelegate {
    static let shared = MacSharing()

    func present(_ payload: SharePayload) {
        let provider = NSItemProvider()
        provider.registerCKShare(payload.share, container: payload.container)
        guard let service = NSSharingService(named: .cloudSharing) else { return }
        service.delegate = self
        service.perform(withItems: [provider])
    }

    func sharingService(_ sharingService: NSSharingService, sourceWindowForShareItems items: [Any],
                        sharingContentScope: UnsafeMutablePointer<NSSharingService.SharingContentScope>) -> NSWindow? {
        NSApp.keyWindow
    }

    func options(for sharingService: NSSharingService, share provider: NSItemProvider) -> NSSharingService.CloudKitOptions {
        [.allowPrivate, .allowReadWrite]
    }
}
#endif
