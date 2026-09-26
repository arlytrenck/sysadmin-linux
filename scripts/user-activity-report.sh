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

usage() { sed -n '2,/^[^#]/p' "$0" | sed '1{/^#$/d;}; $d; s/^# \{0,1\}//'; exit "${1:-0}"; }

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
  # Only accounts that can actually log in: lastlog lists every daemon and
  # service account too, and they all read "Never logged in", which buried
  # the handful of real users under a few dozen system entries.
  lastlog -u 0 | head -n 1
  while IFS=: read -r acct _ _ _ _ _ acct_shell; do
    case "$acct_shell" in */nologin|*/false) continue ;; esac
    lastlog -u "$acct" 2>/dev/null | awk 'NR > 1 && /\*\*Never logged in\*\*/'
  done < /etc/passwd
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

