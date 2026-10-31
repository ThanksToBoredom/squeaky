#!/bin/bash
# Publishes a GitHub release of HEAD with a universal (Apple Silicon + Intel) DMG.
# Used by the Release workflow on every push to main, and works locally too.
#
#   scripts/release.sh                 release if the commits since the last tag warrant one
#   VERSION=1.2.3 scripts/release.sh   force a version
#   DRY_RUN=1 scripts/release.sh       build the DMG but don't publish anything
#
# The version comes from the conventional commits since the last vX.Y.Z tag (see
# scripts/next-version.sh) and is stamped into the app's Info.plist at build time; the build
# number is the commit count. Locally the build runs in a temporary worktree of HEAD, so
# uncommitted changes never end up in a release; HEAD must be pushed.
set -euo pipefail
cd "$(dirname "$0")/.."

git fetch -q origin --tags || true
VERSION="${VERSION:-$(scripts/next-version.sh)}"
if [ -z "$VERSION" ]; then
    echo "No feat, fix, perf or breaking commits since the last release: nothing to release."
    exit 0
fi
TAG="v$VERSION"
COMMIT="$(git rev-parse HEAD)"
BUILD_NUMBER="$(git rev-list --count HEAD)"

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    echo "$TAG already exists." >&2
    exit 1
fi

DMG="$PWD/dist/Squeaky-$VERSION.dmg"
mkdir -p dist

if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    SOURCE="$PWD"
else
    if [ "${DRY_RUN:-0}" != "1" ] && ! git branch -r --contains "$COMMIT" | grep -q .; then
        echo "Push $COMMIT first, so the release matches what's on GitHub." >&2
        exit 1
    fi
    SOURCE="$(mktemp -d)/squeaky-$VERSION"
    git worktree add -q --detach "$SOURCE" "$COMMIT"
    trap 'git worktree remove --force "$SOURCE"' EXIT
fi

echo "Building Squeaky $VERSION (build $BUILD_NUMBER) from ${COMMIT:0:7}"
/usr/libexec/PlistBuddy \
    -c "Set :CFBundleShortVersionString $VERSION" \
    -c "Set :CFBundleVersion $BUILD_NUMBER" \
    "$SOURCE/Resources/Info.plist"
(cd "$SOURCE" && UNIVERSAL=1 scripts/package.sh "$DMG")

if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "Dry run: built $DMG, nothing published."
    exit 0
fi

sed "s/{{VERSION}}/$VERSION/g" .github/release-notes.md > "$SOURCE/.release-notes.md"
gh release create "$TAG" "$DMG" \
    --target "$COMMIT" \
    --title "Squeaky $VERSION" \
    --notes-file "$SOURCE/.release-notes.md" \
    --generate-notes

echo "Released $TAG"
