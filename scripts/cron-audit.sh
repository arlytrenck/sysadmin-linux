#!/usr/bin/env bash
#
# cron-audit.sh — enumerate all scheduled jobs on the box: system crontab,
# /etc/cron.d, /etc/cron.{hourly,daily,weekly,monthly}, and every user's
# crontab. Read-only; useful for a periodic review or an incident where
# persistence via cron is a concern.
#
# Usage:
#   ./cron-audit.sh
#
# Options:
#   -h   Show this help

set -uo pipefail

usage() {
  grep '^#' "$0" | sed -n '2,8p' | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while getopts ":h" opt; do
  case "$opt" in
    h) usage 0 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage 1 ;;
  esac
done

echo "=== /etc/crontab ==="
if [[ -r /etc/crontab ]]; then
  grep -Ev '^\s*(#|$)' /etc/crontab
else
  echo "  (not present or not readable)"
fi

echo
echo "=== /etc/cron.d/* ==="
if [[ -d /etc/cron.d ]]; then
  for f in /etc/cron.d/*; do
    [[ -f "$f" ]] || continue
    echo "--- $f ---"
    grep -Ev '^\s*(#|$)' "$f"
  done
else
  echo "  (directory not present)"
fi

echo
echo "=== Periodic job directories ==="
for dir in /etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly; do
  if [[ -d "$dir" ]]; then
    echo "--- $dir ---"
    find "$dir" -maxdepth 1 -type f -printf '  %f\n' 2>/dev/null
  fi
done

echo
echo "=== systemd timers (if this box uses timers instead of/alongside cron) ==="
if command -v systemctl &>/dev/null; then
  systemctl list-timers --all --no-pager 2>/dev/null | head -n 30
else
  echo "  (systemctl not available)"
fi

echo
echo "=== Per-user crontabs ==="
if [[ -r /etc/passwd ]]; then
  while IFS=: read -r user _ uid _ _ home shell; do
    # Skip obvious system/service accounts with no login shell
    [[ "$shell" == */nologin || "$shell" == */false ]] && continue
    (( uid < 1000 && uid != 0 )) && continue
    entries="$(crontab -l -u "$user" 2>/dev/null | grep -Ev '^\s*(#|$)')"
    if [[ -n "$entries" ]]; then
      echo "--- $user ---"
      echo "$entries"
    fi
  done < /etc/passwd
else
  echo "  (/etc/passwd not readable)"
fi

echo
echo "Done. Review entries for anything unfamiliar, especially jobs that"
echo "download-and-execute, run as root unnecessarily, or point at paths"
echo "under /tmp or other world-writable locations."

