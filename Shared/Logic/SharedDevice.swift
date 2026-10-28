import Foundation

/// A family device (say, a kitchen iPad) that everyone uses. It stays signed in to
/// a parent's iCloud account; each person picks their profile to use it, and parent
/// profiles need the household's parent code. The choice is per device, and the
/// session ends whenever the app leaves the screen.
@MainActor
final class SharedDevice: ObservableObject {
    static let maxAttempts = 5
    static let lockout: TimeInterval = 60

    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.enabledKey)
            if !isEnabled { activeMemberID = nil }
        }
    }
    /// Who is using the device right now; nil shows the profile picker.
    @Published private(set) var activeMemberID: UUID?
    @Published private(set) var lockedUntil: Date?

    private let defaults: UserDefaults
    private let now: () -> Date
    private var failedAttempts = 0
    private static let enabledKey = "sharedDevice.enabled"

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        isEnabled = defaults.bool(forKey: Self.enabledKey)
    }

    func activeMember(in household: Household) -> Member? {
        guard isEnabled, let activeMemberID else { return nil }
        return household.memberList.first { $0.id == activeMemberID }
    }

    /// Kids go straight in; parents need the parent code. Too many wrong codes
    /// in a row locks parent sign-in for a minute.
    func signIn(_ member: Member, code: String? = nil) throws {
        if member.isParent {
            if let lockedUntil, lockedUntil > now() {
                throw ServiceError.notAllowed("Too many wrong codes. Try again in a minute.")
            }
            guard let expected = member.household?.parentCode, code?.trimmed == expected else {
                failedAttempts += 1
                if failedAttempts >= Self.maxAttempts {
                    lockedUntil = now().addingTimeInterval(Self.lockout)
                    failedAttempts = 0
                }
                throw ServiceError.notAllowed("That parent code isn't right.")
            }
            failedAttempts = 0
            lockedUntil = nil
        }
        activeMemberID = member.id
    }

    /// Back to the profile picker.
    func signOut() {
        activeMemberID = nil
    }

    /// Turning shared mode on keeps the parent who did it signed in.
    func enable(as parent: Member) {
        guard parent.isParent else { return }
        isEnabled = true
        activeMemberID = parent.id
    }
}
