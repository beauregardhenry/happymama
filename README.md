# Happy Mama

Household chore tracker for iPhone (iOS 17+, iPhone 14 and later) and Mac (macOS 14+, Intel and Apple silicon).
Parents assign chores with point values; kids mark them done; points are awarded only when a parent approves.

## Build
    brew install xcodegen
    xcodegen generate
    open HappyMama.xcodeproj

* **Try it without iCloud:** pick the `HappyMama-iOS-Local` or `HappyMama-macOS-Local` scheme. Data stays on the device; Family > "Switch user" lets you act as anyone.
* **Real build (iCloud sync + invites):** pick `HappyMama-iOS` / `HappyMama-macOS`, then in Signing & Capabilities set your Team and change the bundle ID in `project.yml` to one you own (the CloudKit container is `iCloud.<bundle id>`). Before shipping, deploy the CloudKit schema to Production in the CloudKit Console.
* Tests: `xcodebuild -scheme HappyMama-macOS-Local -configuration Local -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`

## How it works
* Data: Core Data + CloudKit. The household is shared via `CKShare`; each person signs in with their own Apple ID and picks their profile.
* Roles are enforced in the app (`HouseholdService`), not by CloudKit, so this is built for trusted family use.
