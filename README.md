# Happy Mama

Household chore tracker for iPhone and iPad (iOS 17+, iPhone 14 and later) and Mac (macOS 14+, Intel and Apple silicon).
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

## Contributing and CI
`main` is protected: changes land through pull requests, and the CI checks must pass.

| Check | What it enforces |
|---|---|
| `scripts/check-banned-patterns.sh` | No `as!`, `fatalError(`, `print(` or TODO/FIXME in `Shared/` (held at zero) |
| `scripts/check-test-count.sh` | Number of test methods never drops (`test-count-baseline.txt`) |
| `scripts/check-coverage.sh` | Line coverage outside `Views/` never drops (`coverage-baseline.txt`) |
| `scripts/verify-macos-universal.sh` | The Release Mac app contains both Intel and Apple silicon code |
| CI build jobs | iPhone and Mac build in both the iCloud and Local configurations |

**Ratchets only go up.** Don't edit the baseline files in a feature branch: after a PR merges, the
`coverage-ratchet` and `test-count-ratchet` workflows raise them on `main` themselves (using a deploy
key that is the ruleset's only bypass). To lower one on purpose, run the script with `--update` and
explain why in the commit.
