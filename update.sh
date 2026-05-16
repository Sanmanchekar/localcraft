#!/usr/bin/env bash
# Update the localcraft skill in place — pulls latest from origin/main.
# Works whether you cd into the clone first or call this from anywhere via
# the symlink at ~/.claude/skills/localcraft.
#
# Run any of these:
#   bash ~/.claude/skills/localcraft/update.sh
#   ~/.claude/skills/localcraft/update.sh         # if executable
#   localcraft update                              # if you have the shell function
set -euo pipefail

# Resolve the actual clone directory (follows the symlink if invoked through it)
SKILL_LINK="${HOME}/.claude/skills/localcraft"
if [ -L "$SKILL_LINK" ]; then
    CLONE_DIR="$(readlink "$SKILL_LINK")"
else
    # Fall back to the dir this script lives in
    CLONE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

if [ ! -d "$CLONE_DIR/.git" ]; then
    echo "error: $CLONE_DIR is not a git checkout — was the skill installed via 'git clone'?" >&2
    exit 1
fi

cd "$CLONE_DIR"

before_sha="$(git rev-parse --short HEAD)"
before_msg="$(git log -1 --pretty=%s)"

echo "localcraft is at: $CLONE_DIR"
echo "current: $before_sha — $before_msg"
echo "pulling..."
git pull --ff-only origin main

after_sha="$(git rev-parse --short HEAD)"
after_msg="$(git log -1 --pretty=%s)"

if [ "$before_sha" = "$after_sha" ]; then
    echo ""
    echo "already up to date."
else
    echo ""
    echo "updated: $before_sha → $after_sha"
    echo "latest:  $after_sha — $after_msg"
    echo ""
    echo "changes since your previous version:"
    git log --oneline "${before_sha}..${after_sha}"
    echo ""
    echo "to apply the new spec to an existing .localcraft/ in a target repo:"
    echo "  cd <your-repo> && claude -p '/localcraft refresh'"
fi
