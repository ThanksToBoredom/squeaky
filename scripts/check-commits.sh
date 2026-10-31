#!/bin/bash
# Checks that commit messages follow Conventional Commits (https://www.conventionalcommits.org).
#
#   scripts/check-commits.sh <base>..<head>      every non-merge commit in a range (CI)
#   scripts/check-commits.sh --message-file <f>  one message, e.g. from the commit-msg hook
#   scripts/check-commits.sh --title "<text>"    a pull request title (it becomes the squash commit)
#
# Allowed: <type>(<optional scope>)<optional !>: <description>, where type is one of
# feat fix perf refactor docs test build ci chore style revert. Git's own "Revert …" and
# "fixup!/squash!" messages are allowed too.
set -euo pipefail

TYPES="feat|fix|perf|refactor|docs|test|build|ci|chore|style|revert"
PATTERN="^(${TYPES})(\([a-zA-Z0-9 ._/-]+\))?!?: [^ ].*"
ALLOWED="^(Revert \"|fixup! |squash! |amend! )"

valid() {
    [[ "$1" =~ $PATTERN ]] || [[ "$1" =~ $ALLOWED ]]
}

explain() {
    echo "  Expected: <type>(<scope>)!: <description>, for example:" >&2
    echo "    feat: add login item removal" >&2
    echo "    fix(cleanup): keep the done screen from stalling" >&2
    echo "    feat!: drop macOS 15 support    (! marks a breaking change)" >&2
    echo "  Types: ${TYPES//|/, }" >&2
}

case "${1:-}" in
    --message-file)
        subject="$(grep -v '^#' "$2" | head -n 1)"
        if ! valid "$subject"; then
            echo "✗ Commit message isn't a conventional commit: \"$subject\"" >&2
            explain
            exit 1
        fi
        ;;
    --title)
        if ! valid "$2"; then
            echo "✗ Pull request title isn't a conventional commit: \"$2\"" >&2
            echo "  (Pull requests are squash-merged, so the title becomes the commit on main.)" >&2
            explain
            exit 1
        fi
        echo "✓ Pull request title: $2"
        ;;
    *..*)
        failed=0
        while IFS=$'\t' read -r sha subject; do
            [ -z "$sha" ] && continue
            if valid "$subject"; then
                echo "✓ ${sha:0:7} $subject"
            else
                echo "✗ ${sha:0:7} $subject" >&2
                failed=1
            fi
        done < <(git log --no-merges --format='%H%x09%s' "$1")
        if [ "$failed" = 1 ]; then
            echo "Some commits aren't conventional commits." >&2
            explain
            echo "  Fix them with an interactive rebase (git rebase -i) and force-push the branch." >&2
            exit 1
        fi
        ;;
    *)
        echo "Usage: $0 <base>..<head> | --message-file <file> | --title <text>" >&2
        exit 2
        ;;
esac
