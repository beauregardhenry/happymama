#!/bin/zsh
set -euo pipefail

# Four patterns that should never appear in production app code, all at zero. This ratchets
# structurally rather than numerically: the floor is 0 forever, with no baseline file to manage.
# There is no legitimate reason for any of these counts to rise, so failing the moment one does
# is the whole design.
#
# What to do instead: a forced downcast or fatalError becomes a thrown error or a UI error state
# (see HouseholdService.make and PersistenceController.loadError); a leftover print() is removed
# (use os.Logger); a TODO/FIXME is finished or filed as an issue before merging.

PROJECT_ROOT="${0:A:h:h}"
SOURCE_DIR="$PROJECT_ROOT/Shared"

typeset -a findings
findings=()

check_pattern() {
    local label="$1"
    local grep_pattern="$2"
    local matches
    matches="$(grep -rnE "$grep_pattern" "$SOURCE_DIR" --include='*.swift' || true)"
    if [[ -n "$matches" ]]; then
        findings+=("$label")
        print -u2 ""
        print -u2 "Found ${label}:"
        print -r -- "$matches" | while IFS= read -r line; do
            print -u2 "  ${line#$PROJECT_ROOT/}"
        done
    fi
}

check_pattern "as! (forced downcast)" '\bas!'
check_pattern "fatalError(" 'fatalError\('
check_pattern "print( (debug output left in)" '\bprint\('
check_pattern "TODO/FIXME comment markers" '//\s*(TODO|FIXME)'

if (( ${#findings} > 0 )); then
    print -u2 ""
    print -u2 "Banned-pattern check failed: ${#findings} pattern(s) found in Shared/."
    print -u2 "These patterns hold at zero on main."
    exit 1
fi

print "Banned-pattern check passed: no as!, fatalError(, print(, or TODO/FIXME in Shared/."
