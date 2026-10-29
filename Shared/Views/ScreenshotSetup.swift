import Foundation

/// Lets scripts/take-screenshots.sh stage each App Store screenshot with launch
/// arguments instead of taps. Only Local builds read them; elsewhere every value is nil.
///
///   -screenshotMember Ava       load the demo family if needed and use the app as Ava
///   -screenshotSection rewards  open on that section
enum ScreenshotSetup {
    #if LOCAL_ONLY
    static let member = UserDefaults.standard.string(forKey: "screenshotMember")
    static let section = UserDefaults.standard.string(forKey: "screenshotSection").flatMap(AppSection.init(rawValue:))
    #else
    static let member: String? = nil
    static let section: AppSection? = nil
    #endif

    /// Loads the demo family on first launch and switches to the requested member.
    @MainActor
    static func apply(households: [Household], identity: Identity, sharedDevice: SharedDevice, service: HouseholdService) {
        #if LOCAL_ONLY
        guard let name = member, let userID = identity.userID else { return }
        let household = households.first ?? (try? service.loadDemoHousehold(userID: userID))
        guard let target = household?.memberList.first(where: { $0.displayName == name }) else { return }
        sharedDevice.isEnabled = false
        identity.actAs(target)
        #endif
    }
}
