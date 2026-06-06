#!/usr/bin/env bash
# Push local repo -> pod. Respects .gitignore, deletes stale remote files,
# never touches gitignored stuff on the pod (e.g. outputs/, model caches).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/runpod.env"

# macOS ships rsync 2.6.9; --info=progress2 needs 3.x.
if rsync --version 2>/dev/null | head -1 | grep -qE 'version 3'; then
  PROGRESS="--info=progress2"
else
  PROGRESS="--progress"
fi

echo "↑ syncing  $LOCAL_DIR  ->  $REMOTE_HOST:$REMOTE_DIR"
# The 'protect' filter guarantees --delete NEVER removes remote results, even
# if experiments/*/results/ is ever dropped from .gitignore. This rule only
# affects deletion (not transfer), so results still aren't pushed up — they
# just can't be wiped on the pod. Belt-and-suspenders for "never lose results".
rsync -az --delete $PROGRESS \
  --filter='protect experiments/*/results/***' \
  --filter=':- .gitignore' \
  --exclude='.git/' \
  "$LOCAL_DIR/" "$REMOTE_HOST:$REMOTE_DIR/"
echo "✓ sync complete"
