#!/usr/bin/env bash
#
# security-audit.sh — a lightweight local security sweep: SUID/SGID
# binaries, world-writable files, listening services, users with shell
# access, and sudoers entries. Not a replacement for a real scanner
# (Lynis, OpenSCAP) — just a fast first look.
#
# Usage:
#   ./security-audit.sh [-p /path/to/scan]
#
# Options:
#   -p   Root path to scan for file-permission issues (default: /)
#   -h   Show this help
#
# This script only reads system state; it makes no changes.

set -uo pipefail

SCAN_PATH="/"

usage() {
  grep '^#' "$0" | sed -n '2,10p' | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while getopts ":p:h" opt; do
  case "$opt" in
    p) SCAN_PATH="$OPTARG" ;;
    h) usage 0 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage 1 ;;
    :) echo "Option -$OPTARG requires an argument" >&2; usage 1 ;;
  esac
done

echo "=== SUID/SGID binaries under $SCAN_PATH ==="
find "$SCAN_PATH" -xdev -type f \( -perm -4000 -o -perm -2000 \) -exec ls -la {} \; 2>/dev/null

echo
echo "=== World-writable files under $SCAN_PATH (excluding common safe paths) ==="
find "$SCAN_PATH" -xdev -type f -perm -0002 \
  -not -path "/proc/*" -not -path "/sys/*" -not -path "/tmp/*" -not -path "/dev/*" \
  -exec ls -la {} \; 2>/dev/null

echo
echo "=== World-writable directories without the sticky bit ==="
find "$SCAN_PATH" -xdev -type d -perm -0002 ! -perm -1000 \
  -not -path "/proc/*" -not -path "/sys/*" \
  -exec ls -lda {} \; 2>/dev/null

echo
echo "=== Listening network services ==="
ss -tulpn 2>/dev/null || netstat -tulpn

echo
echo "=== Users with an interactive login shell ==="
awk -F: '$7 !~ /(nologin|false)$/ { print $1 " -> " $7 }' /etc/passwd

echo
echo "=== Users with empty passwords (from /etc/shadow, requires root) ==="
if [[ "$(id -u)" -eq 0 ]]; then
  awk -F: '($2 == "" ) { print $1 }' /etc/shadow
else
  echo "  (skipped: run as root to check /etc/shadow)"
fi

echo
echo "=== sudoers entries ==="
if [[ -r /etc/sudoers ]]; then
  grep -vE '^\s*#|^\s*$' /etc/sudoers
else
  echo "  (skipped: /etc/sudoers not readable)"
fi
if [[ -d /etc/sudoers.d ]]; then
  find /etc/sudoers.d -type f -exec sh -c 'echo "--- {} ---"; grep -vE "^\s*#|^\s*$" "{}"' \; 2>/dev/null
fi

echo
echo "=== Failed login attempts (recent) ==="
if command -v journalctl &>/dev/null; then
  journalctl -u sshd -p warning --since "-24 hours" --no-pager 2>/dev/null | tail -30
elif [[ -r /var/log/auth.log ]]; then
  grep -i "failed" /var/log/auth.log | tail -30
else
  echo "  (no accessible auth log found)"
fi

echo
echo "Done. Review findings above — this is a starting point, not a verdict."

