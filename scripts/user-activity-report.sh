#!/usr/bin/env bash
#
# user-activity-report.sh — summarize who's on the box, who's been on it
# recently, and recent failed login attempts. Useful for routine review or
# as a quick check during an incident.
#
# Usage:
#   ./user-activity-report.sh [-n 20]
#
# Options:
#   -n   Number of recent login/failure entries to show per section
#        (default: 20)
#   -h   Show this help

set -uo pipefail

COUNT=20

usage() {
  grep '^#' "$0" | sed -n '2,9p' | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while getopts ":n:h" opt; do
  case "$opt" in
    n) COUNT="$OPTARG" ;;
    h) usage 0 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage 1 ;;
    :) echo "Option -$OPTARG requires an argument" >&2; usage 1 ;;
  esac
done

echo "=== Currently logged in ==="
who

echo
echo "=== Last $COUNT logins ==="
last -n "$COUNT" 2>/dev/null || echo "  (last command unavailable or no wtmp)"

echo
echo "=== Last $COUNT failed login attempts ==="
if command -v lastb &>/dev/null; then
  lastb -n "$COUNT" 2>/dev/null || echo "  (requires root to read btmp)"
else
  echo "  (lastb not available)"
fi

echo
echo "=== Idle interactive-shell accounts (never logged in, per lastlog) ==="
if command -v lastlog &>/dev/null; then
  lastlog | awk 'NR==1 || /\*\*Never logged in\*\*/'
else
  echo "  (lastlog not available)"
fi

echo
echo "=== Recent sudo usage ==="
if command -v journalctl &>/dev/null; then
  journalctl -t sudo --since "-24 hours" --no-pager 2>/dev/null | tail -n "$COUNT"
elif [[ -r /var/log/auth.log ]]; then
  grep sudo /var/log/auth.log | tail -n "$COUNT"
else
  echo "  (no accessible sudo log found)"
fi

echo
echo "Done."

