#!/usr/bin/env bash
# Pull experiment outputs from the pod back to local. No --delete here, so
# results from earlier runs on your Mac are never wiped.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/runpod.env"

if rsync --version 2>/dev/null | head -1 | grep -qE 'version 3'; then
  PROGRESS="--info=progress2"
else
  PROGRESS="--progress"
fi

echo "↓ pulling ONLY results (experiments/*/results/) from $REMOTE_HOST  ->  $LOCAL_DIR/$RESULTS_SUBDIR"
mkdir -p "$LOCAL_DIR/$RESULTS_SUBDIR"
# CRITICAL: only pull the results/ subfolders, NEVER source code.
#   --include='*/'          recurse into all dirs so we can reach results/
#   --include='*/results/***'  pull each experiment's results/ dir + contents
#   --exclude='*'           drop everything else (your .py / .yaml / .ipynb code)
#   --prune-empty-dirs      don't create empty code-dir scaffolding locally
# No --delete, so local results are never wiped either.
rsync -az --prune-empty-dirs $PROGRESS \
  --include='*/' \
  --include='*/results/***' \
  --exclude='*' \
  "$REMOTE_HOST:${REMOTE_DIR%/}/$RESULTS_SUBDIR/" \
  "$LOCAL_DIR/$RESULTS_SUBDIR/"
echo "✓ results pulled (code left untouched) to $LOCAL_DIR/$RESULTS_SUBDIR"
