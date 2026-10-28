#!/bin/zsh
set -euo pipefail

# Test coverage only ratchets one way. This runs the macOS unit tests with coverage and fails when
# line coverage over the app sources drops below the number recorded in coverage-baseline.txt, so
# a change that adds untested code has to say so out loud instead of quietly diluting the suite.
#
# Shared/Views/ is excluded on purpose: SwiftUI view bodies are the bulk of the UI code and aren't
# exercised by these unit tests; counting them would swamp the signal from the rules in Logic/ and
# Persistence/ with code this suite can't touch. Everything else (including App/) stays in.
#
# Do NOT bump coverage-baseline.txt from a feature branch. The coverage-ratchet workflow
# re-measures on every push to main and commits the raised number itself, so two PRs in flight
# never edit the same line. A feature branch only needs the plain (no-flag) form to pass.
#
#   ./scripts/check-coverage.sh                      measure and enforce (what a PR runs)
#   ./scripts/check-coverage.sh --update-if-higher   raise the baseline if it climbed; never lowers
#   ./scripts/check-coverage.sh --update             rewrite unconditionally (deliberate lowering,
#                                                    with a reason in the commit)

PROJECT_ROOT="${0:A:h:h}"
BASELINE_FILE="$PROJECT_ROOT/coverage-baseline.txt"
RESULT="$PROJECT_ROOT/build/coverage.xcresult"

architecture="${COVERAGE_ARCHITECTURE:-$(uname -m)}"
case "$architecture" in
    arm64|arm64e) architecture="arm64" ;;
    x86_64) ;;
    *)
        print -u2 "Coverage check failed: unsupported architecture '$architecture'."
        exit 1
        ;;
esac

# How far coverage may drift below the baseline before the build fails: small enough to catch a
# deleted test, loose enough to absorb rounding. And how far above it must climb to be worth raising.
TOLERANCE="${COVERAGE_TOLERANCE:-0.25}"
RATCHET_SLACK="${COVERAGE_RATCHET_SLACK:-0.5}"

mode=check
case "${1:-}" in
    --update) mode=update ;;
    --update-if-higher) mode=update-if-higher ;;
    "") ;;
    *)
        print -u2 "Usage: ${0:t} [--update|--update-if-higher]"
        exit 2
        ;;
esac

cd "$PROJECT_ROOT"
[[ -d HappyMama.xcodeproj ]] || xcodegen generate

print "Running the test suite with a fresh coverage profile."
rm -rf "$RESULT"
xcodebuild -project HappyMama.xcodeproj -scheme HappyMama-macOS-Local -configuration Local \
    -destination 'platform=macOS' -derivedDataPath build \
    -enableCodeCoverage YES -resultBundlePath "$RESULT" \
    CODE_SIGNING_ALLOWED=NO test

if [[ ! -d "$RESULT" ]]; then
    print -u2 "Coverage check failed: $RESULT was not produced."
    exit 1
fi

# Sum covered/executable lines over the app target's files, minus Views/. Print the total and the
# least-covered files so a failure points at something actionable rather than just a number.
measured="$(xcrun xccov view --report --json "$RESULT" | /usr/bin/python3 -c '
import json, sys

report = json.load(sys.stdin)
covered = executable = 0
files = []
for target in report["targets"]:
    if not target["name"].endswith(".app"):
        continue
    for f in target["files"]:
        if "/Shared/Views/" in f["path"]:
            continue
        covered += f["coveredLines"]
        executable += f["executableLines"]
        if f["executableLines"] >= 20:
            files.append((100.0 * f["coveredLines"] / f["executableLines"], f["executableLines"], f["path"]))
if executable == 0:
    sys.exit("no app-target coverage found")
print("%.2f %d %d" % (100.0 * covered / executable, covered, executable))
for pct, count, path in sorted(files)[:5]:
    print("%s\t%.1f\t%d" % (path, pct, count))
')"

percent="$(print -r -- "$measured" | head -1 | cut -d" " -f1)"
covered="$(print -r -- "$measured" | head -1 | cut -d" " -f2)"
total_lines="$(print -r -- "$measured" | head -1 | cut -d" " -f3)"

print "Line coverage (app sources outside Views/): ${percent}% (${covered}/${total_lines} lines)"
print "Least-covered files:"
print -r -- "$measured" | tail -n +2 | while IFS=$'\t' read -r file pct count; do
    printf "  %5s%%  %5s lines  %s\n" "$pct" "$count" "${file#$PROJECT_ROOT/}"
done

write_baseline() {
    local written_percent="$1"
    local arm64_baseline intel_baseline
    arm64_baseline="$(sed -n 's/^arm64=//p' "$BASELINE_FILE" 2>/dev/null | tail -1 | tr -d '[:space:]' || true)"
    intel_baseline="$(sed -n 's/^x86_64=//p' "$BASELINE_FILE" 2>/dev/null | tail -1 | tr -d '[:space:]' || true)"
    if [[ "$architecture" == "arm64" ]]; then
        arm64_baseline="$written_percent"
    else
        intel_baseline="$written_percent"
    fi
    cat > "$BASELINE_FILE" <<BASELINE
# Architecture-specific line coverage floors for app sources outside Views/.
# Coverage instrumentation differs between Apple silicon and Intel builds. Raised automatically by
# .github/workflows/coverage-ratchet.yml on every push to main; don't bump it from a feature
# branch (see the header of scripts/check-coverage.sh). Lower one only deliberately, with a reason
# in the commit. A missing line means that architecture hasn't been measured on main yet.
${arm64_baseline:+arm64=$arm64_baseline}
${intel_baseline:+x86_64=$intel_baseline}
BASELINE
}

baseline="$(sed -n "s/^${architecture}=//p" "$BASELINE_FILE" 2>/dev/null | tail -1 | tr -d '[:space:]' || true)"

if [[ "$mode" == "update" ]]; then
    write_baseline "$percent"
    print "${architecture} baseline updated to ${percent}%. Commit coverage-baseline.txt."
    exit 0
fi

if [[ -z "$baseline" ]]; then
    if [[ "$mode" == "update-if-higher" ]]; then
        write_baseline "$percent"
        print "No ${architecture} baseline recorded yet; seeded it at ${percent}%."
    else
        print
        print "No ${architecture} coverage baseline recorded yet, so nothing to enforce."
        print "This is normally seeded by the post-merge coverage-ratchet workflow, not by hand."
    fi
    exit 0
fi

if [[ ! "$baseline" =~ '^[0-9]+(\.[0-9]+)?$' ]]; then
    print -u2 "Coverage check failed: coverage-baseline.txt does not contain a number ('$baseline')."
    exit 1
fi

floor="$(/usr/bin/python3 -c "print('%.2f' % max(0.0, $baseline - $TOLERANCE))")"
verdict="$(/usr/bin/python3 -c "print('below' if $percent < $floor else ('above' if $percent > $baseline + $RATCHET_SLACK else 'held'))")"

print

case "$verdict" in
    below)
        print -u2 "Coverage check failed: ${percent}% is below the ${architecture} ${baseline}% baseline (floor ${floor}%)."
        if [[ "$mode" == "update-if-higher" ]]; then
            print -u2 "The baseline was left untouched; investigate how a regression reached main."
        else
            print -u2 "Add tests for the new code, or lower coverage-baseline.txt deliberately and say why in the commit."
        fi
        exit 1
        ;;
    above)
        if [[ "$mode" == "update-if-higher" ]]; then
            write_baseline "$percent"
            print "${architecture} baseline raised from ${baseline}% to ${percent}%. Committing coverage-baseline.txt."
        else
            print "Coverage rose to ${percent}% from the ${architecture} ${baseline}% baseline."
            print "No action needed: the post-merge ratchet workflow will raise the baseline on main."
        fi
        ;;
    held)
        print "Coverage holds at ${percent}% against the ${architecture} ${baseline}% baseline."
        ;;
esac
