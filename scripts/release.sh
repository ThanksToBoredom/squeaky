#!/bin/bash
# Publishes a GitHub release of the current commit, with a universal (Apple Silicon + Intel) DMG.
# Usage: scripts/release.sh
#
# The version comes from CFBundleShortVersionString in Resources/Info.plist: bump it (and
# CFBundleVersion), commit and push before running. The build happens in a temporary worktree
# of the pushed commit, so uncommitted changes never end up in a release.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)"
TAG="v$VERSION"
COMMIT="$(git rev-parse HEAD)"

git fetch -q origin --tags
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    echo "$TAG already exists. Bump CFBundleShortVersionString in Resources/Info.plist first." >&2
    exit 1
fi
if ! git branch -r --contains "$COMMIT" | grep -q .; then
    echo "Push $COMMIT first, so the release matches what's on GitHub." >&2
    exit 1
fi

WORKTREE="$(mktemp -d)/squeaky-$VERSION"
git worktree add -q --detach "$WORKTREE" "$COMMIT"
trap 'git worktree remove --force "$WORKTREE"' EXIT

DMG="$PWD/dist/Squeaky-$VERSION.dmg"
(cd "$WORKTREE" && UNIVERSAL=1 scripts/package.sh "$DMG")

gh release create "$TAG" "$DMG" \
    --target "$COMMIT" \
    --title "Squeaky $VERSION" \
    --generate-notes \
    --notes "$(cat <<NOTES
## Install

1. Download **Squeaky-$VERSION.dmg** below and open it.
2. Drag **Squeaky** onto **Applications**.
3. Squeaky isn't notarized by Apple yet, so the first time you open it macOS will block it.
   Open **System Settings → Privacy & Security**, scroll down and click **Open Anyway**.

Works on macOS 15 or later, on Apple Silicon and Intel Macs.

> Squeaky deletes files. Caches and logs are deleted permanently; everything else goes to the
> Trash. Review what's selected and keep a backup. Provided as is, without warranty; see the
> disclaimer in the README.
NOTES
)"

git fetch -q origin --tags
echo "Released $TAG: https://github.com/ThanksToBoredom/squeaky/releases/tag/$TAG"
