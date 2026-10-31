#!/bin/bash
# Prints the next release version, worked out from the conventional commits since the last
# release tag (vX.Y.Z), or nothing if no commit since then warrants a release.
#
#   breaking change (type! or a "BREAKING CHANGE:" footer) → major (minor while below 1.0)
#   feat                                                    → minor
#   fix, perf                                               → patch
#   docs, test, build, ci, chore, style, refactor, revert   → no release
#
# Merge commits are ignored; with squash merges the pull request title is the commit.
set -euo pipefail

last="$(git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' 2>/dev/null || true)"
range="${last:+$last..}HEAD"
IFS=. read -r major minor patch <<<"${last#v}"
major="${major:-0}" minor="${minor:-0}" patch="${patch:-0}"

bump=""
while IFS= read -r -d $'\x1e' message; do
    subject="$(printf '%s\n' "$message" | sed -n '1{s/^[[:space:]]*//;p;}')"
    if [[ "$subject" =~ ^[a-z]+(\([^\)]*\))?!: ]] || printf '%s\n' "$message" | grep -q '^BREAKING[ -]CHANGE:'; then
        bump=major
    elif [[ "$subject" =~ ^feat(\([^\)]*\))?: ]]; then
        [ "$bump" = major ] || bump=minor
    elif [[ "$subject" =~ ^(fix|perf)(\([^\)]*\))?: ]]; then
        [ -n "$bump" ] || bump=patch
    fi
done < <(git log --no-merges --format='%B%x1e' "$range")

case "$bump" in
    major) if [ "$major" = 0 ]; then echo "0.$((minor + 1)).0"; else echo "$((major + 1)).0.0"; fi ;;
    minor) echo "$major.$((minor + 1)).0" ;;
    patch) echo "$major.$minor.$((patch + 1))" ;;
    *) ;;
esac
