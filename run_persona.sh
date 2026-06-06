#!/usr/bin/env bash
# Sync -> (install deps if changed) -> run the experiment INSIDE tmux on the pod.
#
# Because the job runs in tmux on the pod, it KEEPS RUNNING even if your laptop
# disconnects, changes wifi/VPN, or goes to sleep. You just reattach to watch.
#
#   run-persona self_recognition_dev            # sync, deps, launch, attach
#   run-persona --no-deps self_recognition_dev  # skip the dependency check
#   run-persona --attach                        # reattach to a running job
#   run-persona --status                        # is it running? show recent log
#   run-persona --stop                          # cancel the running job
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/runpod.env"

# tmux session name + log/flag paths on the pod. The log/flag live in /tmp so
# they are never touched by sync_up's --delete and are always readable.
SESSION="${POD_TMUX_SESSION:-persona}"
LOGFILE="/tmp/persona_run.log"
FLAG="/tmp/persona_running"

MODE="run"
SKIP_DEPS=0
RUN_ARGS=()
for a in "$@"; do
  case "$a" in
    --attach|attach) MODE="attach" ;;
    --status|status) MODE="status" ;;
    --stop|stop)     MODE="stop" ;;
    --no-deps)       SKIP_DEPS=1 ;;
    *)               RUN_ARGS+=("$a") ;;
  esac
done

# Reattach to the live job. The job survives even if THIS connection drops.
attach_session() {
  echo ""
  echo "Attaching to your run (tmux session '$SESSION')."
  echo "  • To LEAVE it running and return to your Mac:  press Ctrl-b, then d"
  echo "  • To CANCEL the run for good:                  press Ctrl-c"
  echo "  (If your wifi drops or you close your laptop, the run keeps going —"
  echo "   just reconnect later with:  run-persona --attach)"
  echo ""
  ssh -t "$REMOTE_HOST" "tmux attach -t $(printf %q "$SESSION")" || true
}

# ── --status ──────────────────────────────────────────────────────────────
if [ "$MODE" = "status" ]; then
  ssh "$REMOTE_HOST" bash -s -- "$SESSION" "$LOGFILE" "$FLAG" <<'REMOTE'
SESSION="$1"; LOGFILE="$2"; FLAG="$3"
if tmux has-session -t "$SESSION" 2>/dev/null; then
  if [ -f "$FLAG" ]; then
    echo "● RUNNING — your experiment is executing in tmux session '$SESSION'."
    echo "  Watch it live:  run-persona --attach"
  else
    echo "■ DONE / STOPPED — the session exists but no experiment is running."
    echo "  It finished or crashed. Check the log below, then run 'pull-results'."
  fi
  echo "----------------------- last 25 log lines -----------------------"
  tail -n 25 "$LOGFILE" 2>/dev/null || echo "(no log yet)"
else
  echo "✗ Nothing running — no tmux session named '$SESSION' on the pod."
fi
REMOTE
  exit 0
fi

# ── --stop ────────────────────────────────────────────────────────────────
if [ "$MODE" = "stop" ]; then
  ssh "$REMOTE_HOST" "tmux kill-session -t $(printf %q "$SESSION") 2>/dev/null && echo '✓ run stopped' || echo '(nothing was running)'"
  exit 0
fi

# ── --attach ──────────────────────────────────────────────────────────────
if [ "$MODE" = "attach" ]; then
  if ssh "$REMOTE_HOST" "tmux has-session -t $(printf %q "$SESSION")" 2>/dev/null; then
    attach_session
  else
    echo "✗ No running session to attach to."
    echo "  Start one with:  run-persona <config>"
  fi
  exit 0
fi

# ── run (default) ───────────────────────────────────────────────────────────

# 1. Always sync first — the freshness guarantee.
"$SCRIPT_DIR/sync_up.sh"

# 2. Install deps only when the requirements file changed. The marker file is
#    keyed by a hash of REQUIREMENTS_FILE and lives in REMOTE_DIR. Since the
#    pod is ephemeral, the first run-persona of the day always reinstalls; the
#    marker just prevents repeat reinstalls within a single pod's lifetime.
#    md5sum runs on the pod (Linux), not on the Mac.
if [ "$SKIP_DEPS" -eq 0 ]; then
  ssh "$REMOTE_HOST" bash -s <<EOF
set -euo pipefail
cd "$REMOTE_DIR"
if [ -f "$REQUIREMENTS_FILE" ]; then
  HASH=\$(md5sum "$REQUIREMENTS_FILE" | awk '{print \$1}')
  if [ ! -f ".deps-\$HASH" ]; then
    echo "⚙ installing dependencies ($REQUIREMENTS_FILE changed)…"
    $INSTALL_CMD
    rm -f .deps-* 2>/dev/null || true
    touch ".deps-\$HASH"
  else
    echo "✓ dependencies up to date"
  fi
else
  echo "⚠ no $REQUIREMENTS_FILE found in $REMOTE_DIR — skipping dependency install"
  echo "  (check REQUIREMENTS_FILE in runpod.env if you expected deps to install)"
fi
EOF
fi

# 3. Launch the experiment INSIDE tmux on the pod, logging to LOGFILE. The job
#    is detached from this SSH connection, so it survives disconnects. We pass
#    everything as positional args into a literal heredoc to dodge quoting bugs.
echo "▶ launching on the pod (in tmux — survives disconnects): $RUN_ENTRYPOINT ${RUN_ARGS[*]:-}"
ssh "$REMOTE_HOST" bash -s -- "$REMOTE_DIR" "$SESSION" "$LOGFILE" "$FLAG" "$RUN_ENTRYPOINT" ${RUN_ARGS[@]+"${RUN_ARGS[@]}"} <<'REMOTE'
set -uo pipefail
REMOTE_DIR="$1"; SESSION="$2"; LOGFILE="$3"; FLAG="$4"; ENTRY="$5"; shift 5

# Make sure tmux is installed (install quietly if the pod doesn't have it).
if ! command -v tmux >/dev/null 2>&1; then
  echo "⚙ installing tmux on the pod…"
  if ! { apt-get update >/dev/null 2>&1 && apt-get install -y tmux >/dev/null 2>&1; }; then
    echo "✗ could not install tmux automatically."
    echo "  In the RunPod web terminal run:  apt-get update && apt-get install -y tmux"
    exit 1
  fi
fi

# Don't clobber a job that's already running.
if tmux has-session -t "$SESSION" 2>/dev/null && [ -f "$FLAG" ]; then
  echo "✗ A run is already in progress (tmux session '$SESSION')."
  echo "  Watch it:  run-persona --attach      Stop it:  run-persona --stop"
  exit 2
fi

# Build the experiment command, escaping each user-supplied arg.
CMD="$ENTRY"
for a in "$@"; do CMD="$CMD $(printf %q "$a")"; done

# Replace any leftover (finished) session of the same name, then launch fresh.
# The launcher sets a 'running' flag for the duration, tees output to the log,
# clears the flag when done, and drops to a shell so the final output stays
# visible when you attach.
tmux kill-session -t "$SESSION" 2>/dev/null || true
rm -f "$FLAG"
tmux new-session -d -s "$SESSION" \
  "cd $(printf %q "$REMOTE_DIR") && touch $(printf %q "$FLAG"); ($CMD) 2>&1 | tee $(printf %q "$LOGFILE"); rm -f $(printf %q "$FLAG"); echo; echo '================= run finished ================='; echo 'Leave as-is: Ctrl-b then d   |   Close this window: type exit'; exec bash"
echo "✓ started in tmux. attaching for live output…"
REMOTE

# 4. Attach so you see live output now. The job keeps running even if this drops.
attach_session
