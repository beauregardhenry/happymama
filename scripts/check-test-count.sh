#!/bin/zsh
set -euo pipefail

# Test count only ratchets one way: fails when the number of test methods drops below the number
# recorded in test-count-baseline.txt. Coverage mostly catches a deleted test, but a raw count is a
# more direct signal -- a test quietly commented out, renamed away from the testFoo() pattern, or
# lost in a merge conflict shows up here even when the coverage percentage barely moves.
#
# Counting is static (a grep over `func test...()` in Tests/), so this is fast and needs no Xcode.
#
# Do NOT bump test-count-baseline.txt from a feature branch. The test-count-ratchet workflow
# re-measures on every push to main and commits the raised number itself, so two PRs in flight
# never edit the same line. A feature branch only needs the plain (no-flag) form to pass.
#
#   ./scripts/check-test-count.sh                      measure and enforce (what a PR runs)
#   ./scripts/check-test-count.sh --update-if-higher   raise the baseline if it climbed; never lowers
#   ./scripts/check-test-count.sh --update             rewrite unconditionally (deliberate lowering,
#                                                      with a reason in the commit)

PROJECT_ROOT="${0:A:h:h}"
BASELINE_FILE="$PROJECT_ROOT/test-count-baseline.txt"

count="$(grep -rhoE 'func test[A-Za-z0-9_]+\(\)' "$PROJECT_ROOT"/Tests/*.swift 2>/dev/null | wc -l | tr -d '[:space:]')"
print "Test count: ${count}"

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

write_baseline() {
    cat > "$BASELINE_FILE" <<BASELINE
# Test-method-count floor. Raised automatically by .github/workflows/test-count-ratchet.yml on
# every push to main; don't bump it from a feature branch (see the header of
# scripts/check-test-count.sh). Lower it only deliberately, with a reason in the commit.
tests=$1
BASELINE
}

baseline="$(sed -n 's/^tests=//p' "$BASELINE_FILE" 2>/dev/null | tail -1 | tr -d '[:space:]' || true)"

if [[ "$mode" == "update" ]]; then
    write_baseline "$count"
    print "Baseline updated to ${count}. Commit test-count-baseline.txt."
    exit 0
fi

if [[ -z "$baseline" ]]; then
    if [[ "$mode" == "update-if-higher" ]]; then
        write_baseline "$count"
        print "No baseline recorded yet; seeded it at ${count}."
    else
        print "No test-count baseline recorded yet, so nothing to enforce."
    fi
    exit 0
fi

if (( count < baseline )); then
    print -u2 "Test count check failed: ${count} is below the ${baseline} baseline."
    print -u2 "A test was removed, renamed away from the testFoo() pattern, or commented out."
    print -u2 "Add tests back, or lower test-count-baseline.txt deliberately and say why in the commit."
    exit 1
elif (( count > baseline )); then
    print "Test count rose to ${count} from the ${baseline} baseline."
    if [[ "$mode" == "update-if-higher" ]]; then
        write_baseline "$count"
        print "Baseline raised. Committing test-count-baseline.txt."
    else
        print "No action needed: the post-merge ratchet workflow will raise the baseline on main."
    fi
else
    print "Test count holds at ${count}."
fi
