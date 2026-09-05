#!/usr/bin/env bash
#
# listening-ports-audit.sh — list every listening TCP/UDP socket with its
# owning process, and optionally flag anything not on an allowlist.
#
# Usage:
#   ./listening-ports-audit.sh [-a /path/to/allowlist.txt]
#
# Options:
#   -a   Allowlist file: one "tcp:PORT" or "udp:PORT" per line, '#' comments
#        and blank lines ignored. Anything listening that isn't on this
#        list is flagged.
#   -h   Show this help
#
# Without -a this is purely informational (exit 0). With -a, a listening
# socket not on the list makes the script exit 1.
#
# Requires `ss` (iproute2); process names require root for other users'
# sockets.

set -uo pipefail

ALLOWLIST=""

usage() {
  grep '^#' "$0" | sed -n '2,15p' | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while getopts ":a:h" opt; do
  case "$opt" in
    a) ALLOWLIST="$OPTARG" ;;
    h) usage 0 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage 1 ;;
    :) echo "Option -$OPTARG requires an argument" >&2; usage 1 ;;
  esac
done

command -v ss >/dev/null 2>&1 || { echo "ss (iproute2) not found." >&2; exit 2; }

if [[ -n "$ALLOWLIST" && ! -f "$ALLOWLIST" ]]; then
  echo "Allowlist file '$ALLOWLIST' not found." >&2
  exit 2
fi

echo "=== Listening TCP sockets ==="
ss -tlnp 2>/dev/null

echo
echo "=== Listening UDP sockets ==="
ss -ulnp 2>/dev/null

if [[ -z "$ALLOWLIST" ]]; then
  echo
  echo "No allowlist given (-a) — informational only."
  exit 0
fi

declare -A allowed
while IFS= read -r line; do
  line="${line%%#*}"
  line="$(echo "$line" | tr -d '[:space:]')"
  [[ -n "$line" ]] && allowed["$line"]=1
done < "$ALLOWLIST"

mapfile -t seen < <(
  {
    ss -tln 2>/dev/null | awk 'NR>1 {print $4}' | sed -E 's/.*:([0-9]+)$/tcp:\1/'
    ss -uln 2>/dev/null | awk 'NR>1 {print $4}' | sed -E 's/.*:([0-9]+)$/udp:\1/'
  } | sort -u
)

flagged=0
echo
echo "=== Ports not on $ALLOWLIST ==="
for key in "${seen[@]}"; do
  if [[ -z "${allowed[$key]:-}" ]]; then
    echo "  FLAG: $key is listening but not allowlisted"
    flagged=1
  fi
done

if (( flagged )); then
  echo
  echo "RESULT: unexpected listening port(s) found."
  exit 1
fi

echo
echo "RESULT: every listening port is allowlisted."
