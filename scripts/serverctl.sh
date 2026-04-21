#!/usr/bin/env bash
set -euo pipefail

SERVER_DIR="${SERVER_DIR:-/data/server}"
PROC_PATTERN='WindroseServer-Win64-Shipping\.exe'

usage() {
    cat <<EOF
usage: serverctl <command>

  status   show whether the server process is running
  stop     send SIGTERM to the server (graceful shutdown)
  logs     tail the latest Windrose log file
  invite   print the InviteCode from ServerDescription.json
EOF
}

cmd="${1:-}"
case "$cmd" in
    status)
        if pgrep -fa "$PROC_PATTERN"; then
            exit 0
        else
            echo "not running"
            exit 1
        fi
        ;;
    stop)
        pkill -TERM -f "$PROC_PATTERN"
        ;;
    logs)
        log_dir="$SERVER_DIR/R5/Saved/Logs"
        latest="$(ls -1t "$log_dir"/*.log 2>/dev/null | head -n1 || true)"
        if [[ -z "$latest" ]]; then
            echo "no logs found in $log_dir"
            exit 1
        fi
        exec tail -F "$latest"
        ;;
    invite)
        desc="$SERVER_DIR/R5/ServerDescription.json"
        if [[ ! -f "$desc" ]]; then
            echo "ServerDescription.json not found at $desc"
            exit 1
        fi
        grep -oE '"InviteCode"[[:space:]]*:[[:space:]]*"[^"]*"' "$desc" \
            | head -n1 \
            | sed -E 's/.*"InviteCode"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/'
        ;;
    ""|-h|--help)
        usage
        ;;
    *)
        usage
        exit 2
        ;;
esac
