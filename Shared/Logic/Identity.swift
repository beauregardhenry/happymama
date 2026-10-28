import Foundation
import CloudKit

/// Who is using this device. In normal builds that's the signed-in iCloud account
/// (its CloudKit user record name is stable across the person's devices). In
/// `LOCAL_ONLY` builds there's no iCloud, so identity is a local value that can
/// be switched to any household member for testing.
@MainActor
final class Identity: ObservableObject {
    enum Status: Equatable {
        case checking
        case available
        case unavailable(String)
    }

    @Published private(set) var userID: String?
    @Published private(set) var status: Status = .checking
    private var observer: NSObjectProtocol?

    func start() {
        #if !LOCAL_ONLY
        observer = NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        #endif
        Task { await refresh() }
    }

    func refresh() async {
        #if LOCAL_ONLY
        let key = "localUserID"
        if let stored = UserDefaults.standard.string(forKey: key) {
            userID = stored
        } else {
            let fresh = "local-" + UUID().uuidString
            UserDefaults.standard.set(fresh, forKey: key)
            userID = fresh
        }
        status = .available
        #else
        let container = CKContainer(identifier: AppConfig.containerID)
        do {
            switch try await container.accountStatus() {
            case .available:
                userID = try await container.userRecordID().recordName
                status = .available
            case .noAccount:
                userID = nil
                status = .unavailable("Sign in to iCloud in Settings so your household can sync between devices.")
            case .restricted:
                userID = nil
                status = .unavailable("iCloud is restricted on this device.")
            case .temporarilyUnavailable:
                userID = nil
                status = .unavailable("iCloud is temporarily unavailable. Try again in a moment.")
            default:
                userID = nil
                status = .unavailable("Couldn't determine your iCloud status.")
            }
        } catch {
            userID = nil
            status = .unavailable(error.localizedDescription)
        }
        #endif
    }

    #if LOCAL_ONLY
    /// Testing aid: act as another household member on this device.
    func actAs(_ member: Member) {
        guard let id = member.appleUserID else { return }
        UserDefaults.standard.set(id, forKey: "localUserID")
        userID = id
    }
    #endif
}
