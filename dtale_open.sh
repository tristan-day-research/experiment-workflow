#!/usr/bin/env bash
#
# dtale-open — open a .json/.jsonl/.csv file in d-Tale in your browser.
#
# Starts a d-Tale server for the file in the background and opens your browser
# to it, then returns immediately so the terminal is free for the next file.
# Each file gets its own server (on its own port); the data-loading and server
# live in dtale_loader.py.
#
# Usage:
#   dtale-open path/to/data.json
#
# How it picks Python:
#   1. If $DTALE_PYTHON is set, use that.
#   2. Otherwise, try a list of likely interpreters and use the first one
#      that has d-Tale installed.
#
# Override the interpreter for good by adding to your ~/.zshrc:
#   export DTALE_PYTHON=/path/to/python
#
set -euo pipefail

FILE="${1:-}"

if [[ -z "$FILE" ]]; then
  echo "Usage: dtale-open <file.json|file.jsonl|file.csv>" >&2
  exit 1
fi

if [[ ! -f "$FILE" ]]; then
  echo "dtale-open: file not found: $FILE" >&2
  exit 1
fi

# Resolve to an absolute path so the Python side doesn't depend on cwd.
FILE="$(cd "$(dirname "$FILE")" && pwd)/$(basename "$FILE")"

# --- Find a Python that has d-Tale installed -------------------------------
CANDIDATES=()
if [[ -n "${DTALE_PYTHON:-}" ]]; then
  CANDIDATES+=("$DTALE_PYTHON")
fi
CANDIDATES+=(
  "$HOME/miniconda3/bin/python"
  "$(command -v python3 || true)"
  "$(command -v python || true)"
)

PYTHON=""
for c in "${CANDIDATES[@]}"; do
  [[ -z "$c" ]] && continue
  if "$c" -c "import dtale" >/dev/null 2>&1; then
    PYTHON="$c"
    break
  fi
done

if [[ -z "$PYTHON" ]]; then
  echo "dtale-open: could not find a Python with d-Tale installed." >&2
  echo "  Install it:  python3 -m pip install dtale" >&2
  echo "  Or set DTALE_PYTHON to a Python that has it." >&2
  exit 1
fi

echo "dtale-open: using $PYTHON"
echo "dtale-open: loading $FILE"

# --- Hand off to Python, detached ------------------------------------------
# We launch the Python loader fully detached (nohup + & + disown) so the
# launcher returns immediately and the prompt is free for the next file. The
# loader keeps running in the background, holding the d-Tale web server open
# (it calls instance.join() and blocks there). Because it's detached, that
# block does not tie up your shell.
#
# Each file gets its own d-Tale server on its own port. (A single shared
# server doesn't work across processes: d-Tale keeps its data in the process
# that started the server, so data loaded by a later, separate process never
# reaches it.) We pick a free port here so the URL is known up front, then
# pass it to the detached loader.
#
# The loader writes the server URL to a temp file; we poll for it, open the
# browser, then return.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOADER="$SCRIPT_DIR/dtale_loader.py"
URL_FILE="$(mktemp -t dtale-open.XXXXXX)"
LOG_FILE="$(mktemp -t dtale-open-log.XXXXXX)"

if [[ ! -f "$LOADER" ]]; then
  echo "dtale-open: loader not found at $LOADER" >&2
  exit 1
fi

# Pick a free TCP port (ask the OS for an ephemeral one and reuse the number).
DTALE_PORT="$("$PYTHON" -c 'import socket; s=socket.socket(); s.bind(("",0)); print(s.getsockname()[1]); s.close()')"

nohup "$PYTHON" "$LOADER" "$FILE" "$URL_FILE" "$DTALE_PORT" >"$LOG_FILE" 2>&1 &
LOADER_PID=$!
disown "$LOADER_PID" 2>/dev/null || true

# Poll for the URL the loader writes once the server is up (give it ~30s).
URL=""
for _ in $(seq 1 150); do
  if [[ -s "$URL_FILE" ]]; then
    URL="$(cat "$URL_FILE")"
    break
  fi
  # If the loader died before writing a URL, bail with its output.
  if ! kill -0 "$LOADER_PID" 2>/dev/null && [[ ! -s "$URL_FILE" ]]; then
    echo "dtale-open: failed to start d-Tale:" >&2
    cat "$LOG_FILE" >&2
    rm -f "$URL_FILE" "$LOG_FILE"
    exit 1
  fi
  sleep 0.2
done

rm -f "$URL_FILE"

if [[ -z "$URL" ]]; then
  echo "dtale-open: timed out waiting for d-Tale to start. Log:" >&2
  cat "$LOG_FILE" >&2
  exit 1
fi

rm -f "$LOG_FILE"

# The URL is written before the server finishes binding (the loader blocks
# inside d-Tale once it starts the server). Wait until it actually responds so
# the browser doesn't open on a connection error. ~15s budget.
for _ in $(seq 1 75); do
  if curl -fsS -o /dev/null --max-time 1 "$URL" 2>/dev/null; then
    break
  fi
  sleep 0.2
done

echo "dtale-open: serving at $URL"
open "$URL"   # macOS: open the d-Tale instance in the default browser
echo "dtale-open: ready — terminal is free for the next file."
