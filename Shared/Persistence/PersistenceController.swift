import CoreData
import CloudKit
import os

enum AppConfig {
    /// Set in Info.plist as `iCloud.<bundle id>`.
    static var containerID: String {
        (Bundle.main.object(forInfoDictionaryKey: "CloudKitContainerID") as? String) ?? "iCloud.com.happymama.HappyMama"
    }
}

/// Owns the Core Data stack.
///
/// In `.cloud` mode there are two stores, mirroring CloudKit's private and shared
/// databases. A household you create lives in the private store and is shared out
/// with a `CKShare`; a household you were invited to lives in the shared store.
final class PersistenceController {
    enum Mode { case cloud, local, inMemory }

    let mode: Mode
    let container: NSPersistentContainer
    private(set) var privateStore: NSPersistentStore?
    private(set) var sharedStore: NSPersistentStore?
    private let log = Logger(subsystem: "com.happymama", category: "persistence")

    var viewContext: NSManagedObjectContext { container.viewContext }

    init(mode: Mode) {
        self.mode = mode
        let model = HappyMamaModel.shared
        switch mode {
        case .cloud:
            container = NSPersistentCloudKitContainer(name: "HappyMama", managedObjectModel: model)
        case .local, .inMemory:
            container = NSPersistentContainer(name: "HappyMama", managedObjectModel: model)
        }

        let dir = NSPersistentContainer.defaultDirectoryURL()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        func description(file: String, scope: CKDatabase.Scope?) -> NSPersistentStoreDescription {
            let d = NSPersistentStoreDescription(url: dir.appendingPathComponent(file))
            d.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            d.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            if let scope {
                let options = NSPersistentCloudKitContainerOptions(containerIdentifier: AppConfig.containerID)
                options.databaseScope = scope
                d.cloudKitContainerOptions = options
            }
            return d
        }

        switch mode {
        case .cloud:
            container.persistentStoreDescriptions = [
                description(file: "HappyMama-private.sqlite", scope: .private),
                description(file: "HappyMama-shared.sqlite", scope: .shared),
            ]
        case .local:
            container.persistentStoreDescriptions = [description(file: "HappyMama-local.sqlite", scope: nil)]
        case .inMemory:
            let d = NSPersistentStoreDescription()
            d.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [d]
        }

        container.loadPersistentStores { [log] _, error in
            if let error {
                log.error("Failed to load store: \(error.localizedDescription)")
                fatalError("Unable to load persistent stores: \(error)")
            }
        }

        let stores = container.persistentStoreCoordinator.persistentStores
        privateStore = stores.first
        if mode == .cloud { sharedStore = stores.last }

        viewContext.automaticallyMergesChangesFromParent = true
        viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        viewContext.name = "view"
    }

    /// True when this household is the user's own (not one they were invited to).
    func isOwner(of household: Household) -> Bool {
        guard mode == .cloud else { return true }
        return household.objectID.persistentStore === privateStore
    }

    // MARK: Sharing

    /// Returns the household's `CKShare`, creating it the first time.
    func share(_ household: Household) async throws -> (CKShare, CKContainer) {
        guard let cloud = container as? NSPersistentCloudKitContainer else {
            throw ServiceError.invalid("Inviting people needs iCloud, which isn't available in this build.")
        }
        if let existing = try cloud.fetchShares(matching: [household.objectID])[household.objectID] {
            return (existing, CKContainer(identifier: AppConfig.containerID))
        }
        let (_, share, ckContainer) = try await cloud.share([household], to: nil)
        return (share, ckContainer)
    }

    /// Called when the user taps an invitation link.
    func accept(_ metadata: CKShare.Metadata) {
        guard let cloud = container as? NSPersistentCloudKitContainer, let sharedStore else { return }
        cloud.acceptShareInvitations(from: [metadata], into: sharedStore) { [log] _, error in
            if let error { log.error("Accepting share failed: \(error.localizedDescription)") }
        }
    }
}
