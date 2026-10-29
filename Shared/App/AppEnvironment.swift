import CoreData
import Combine

/// App-wide singletons. Created at launch (not by a view) so that a background
/// launch caused by a CloudKit push can still import data and post notifications.
@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()

    let persistence: PersistenceController
    let identity = Identity()
    let service: HouseholdService
    let notifier = Notifier()
    let sharedDevice = SharedDevice()
    private var changeObserver: AnyCancellable?
    private var started = false

    private init() {
        #if LOCAL_ONLY
        persistence = PersistenceController(mode: .local)
        service = HouseholdService(persistence: persistence, autoClaimNewMembers: true)
        #else
        persistence = PersistenceController(mode: .cloud)
        service = HouseholdService(persistence: persistence)
        #endif
    }

    func start() {
        guard !started else { return }
        started = true
        notifier.onAction = { [weak self] action, id, note in await self?.perform(action, on: id, note: note) }
        notifier.start()
        identity.start()
        changeObserver = NotificationCenter.default
            .publisher(for: .NSManagedObjectContextObjectsDidChange, object: persistence.viewContext)
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncNotifications() }
    }

    /// The household on this device and the account owner's profile in it.
    private func currentHousehold() -> (Household, Member)? {
        guard let userID = identity.userID else { return nil }
        let request = Household.fetchRequest()
        request.fetchLimit = 1
        guard let household = (try? persistence.viewContext.fetch(request))?.first as? Household,
              let me = household.memberList.first(where: { $0.appleUserID == userID }) else { return nil }
        return (household, me)
    }

    func syncNotifications() {
        guard let (household, me) = currentHousehold() else { return }
        // Tidy up anything two devices both created while offline before notifying about it.
        try? service.resolveSyncDuplicates(in: household)
        notifier.sync(household: household, me: me)
        WidgetSnapshot.publish(household: household, me: me)
        // Lets Siri offer "I finished the dishes" with the current chore names.
        HappyMamaShortcuts.updateAppShortcutParameters()
    }

    /// For Siri and Shortcuts, which can run before any window opens.
    func intentContext() async -> (household: Household, me: Member, service: HouseholdService)? {
        start()
        if identity.userID == nil { await identity.refresh() }
        guard let (household, me) = currentHousehold() else { return nil }
        return (household, me, service)
    }

    /// A parent tapped Approve, Send back or Deny on a notification.
    private func perform(_ action: Notifier.Action, on id: UUID, note: String?) async {
        // A tap can launch the app in the background before the iCloud identity has loaded.
        if identity.userID == nil { await identity.refresh() }
        guard let (household, me) = currentHousehold() else { return }
        notifier.handle(action, on: id, note: note, household: household, me: me, service: service)
        notifier.sync(household: household, me: me)
    }
}
