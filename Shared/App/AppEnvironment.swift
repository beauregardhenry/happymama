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
        notifier.start()
        identity.start()
        changeObserver = NotificationCenter.default
            .publisher(for: .NSManagedObjectContextObjectsDidChange, object: persistence.viewContext)
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncNotifications() }
    }

    func syncNotifications() {
        guard let userID = identity.userID else { return }
        let request = Household.fetchRequest()
        request.fetchLimit = 1
        guard let household = (try? persistence.viewContext.fetch(request))?.first as? Household,
              let me = household.memberList.first(where: { $0.appleUserID == userID }) else { return }
        notifier.sync(household: household, me: me)
    }
}
