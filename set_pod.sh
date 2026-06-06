#!/usr/bin/env bash
# Rewrite the pod's Host block in ~/.ssh/config from the SSH command RunPod
# gives you. The alias name is taken from REMOTE_HOST in runpod.env, so it
# always matches what sync_up / pull_results / run_persona expect.
#
#   set-pod ssh root@69.30.85.123 -p 22064 -i ~/.ssh/id_ed25519
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/runpod.env"
HOST_ALIAS="$REMOTE_HOST"
CONFIG="$HOME/.ssh/config"

USER_HOST=""; PORT="22"; IDENTITY=""
while [ $# -gt 0 ]; do
  case "$1" in
    ssh)  shift ;;
    -p)   PORT="$2";     shift 2 ;;
    -i)   IDENTITY="$2"; shift 2 ;;
    *@*)  USER_HOST="$1"; shift ;;
    *)    shift ;;
  esac
done

if [ -z "$USER_HOST" ]; then
  echo "Usage: set-pod ssh root@<ip> -p <port> -i <keyfile>"
  echo "(just paste the whole SSH command from the RunPod page)"
  exit 1
fi

POD_USER="${USER_HOST%@*}"
POD_HOST="${USER_HOST#*@}"
[ -z "$IDENTITY" ] && IDENTITY="$HOME/.ssh/id_ed25519"

mkdir -p "$HOME/.ssh"; touch "$CONFIG"; cp "$CONFIG" "$CONFIG.bak"

# Drop any existing block for this alias, then append a fresh one.
awk -v alias="$HOST_ALIAS" '
  /^[Hh]ost / { skip = ($2 == alias) ? 1 : 0 }
  skip == 0  { print }
' "$CONFIG.bak" > "$CONFIG"

cat >> "$CONFIG" <<EOF

Host $HOST_ALIAS
    HostName $POD_HOST
    User $POD_USER
    Port $PORT
    IdentityFile $IDENTITY
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    ServerAliveInterval 30
    ServerAliveCountMax 6
    TCPKeepAlive yes
EOF

echo "✓ '$HOST_ALIAS' now points at $POD_USER@$POD_HOST  (port $PORT)"
echo ""
echo "Next: add your SSH key via the RunPod web terminal (see README Step 3),"
echo "then install rsync + tmux on the pod:"
echo "  apt-get update && apt-get install -y rsync tmux"
