#!/bin/zsh
# Create an agent worktree off latest origin/main with a warm build cache.
#
# Usage: zsh scripts/agent-worktree.sh <branch> [slug]
#   branch  e.g. feat/halo-header  (also used to derive the slug when omitted)
#   slug    directory name under .claude/worktrees/ (default: branch with / -> -)
#
# Seeds the new worktree's .build from the main checkout via APFS clonefile
# (copy-on-write, ~instant) so agents skip the cold dependency build. Keep the
# main checkout's cache warm by running `swift build` there after each merge —
# building in the main worktree is fine; editing it is not.
set -euo pipefail

branch=${1:?usage: agent-worktree.sh <branch> [slug]}
slug=${2:-${branch//\//-}}

# Resolve the main checkout (first entry of `git worktree list` is always the
# primary working tree, regardless of where the script is invoked from).
root=$(git worktree list --porcelain | head -1 | cut -d' ' -f2)
dest="$root/.claude/worktrees/$slug"

if [[ -e $dest ]]; then
  echo "error: $dest already exists" >&2
  exit 1
fi

git -C "$root" fetch origin main
git -C "$root" worktree add "$dest" -b "$branch" origin/main

if [[ -d $root/.build ]]; then
  # -c = clonefile; falls back to a regular copy on non-APFS volumes.
  cp -Rc "$root/.build" "$dest/.build" 2>/dev/null || cp -R "$root/.build" "$dest/.build"
  echo "seeded .build cache from $root/.build"
else
  echo "note: no .build in main checkout — first build will be cold." \
       "Run 'DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build' in $root to fix for next time."
fi

cat <<EOF

worktree ready: $dest
build with:
  cd $dest
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
EOF
