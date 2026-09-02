#!/usr/bin/env bash
#
# service-health-check.sh — check that a list of systemd units are active,
# and optionally restart any that have failed or stopped.
#
# Usage:
#   ./service-health-check.sh -u nginx,sshd,docker [--restart]
#
# Options:
#   -u   Comma-separated list of systemd unit names to check (required)
#   --restart   Attempt to restart any unit that is not active
#   -h   Show this help
#
# Exits non-zero if any unit was unhealthy (even if restart was attempted).

set -euo pipefail

UNITS=""
DO_RESTART=0

usage() {
  grep '^#' "$0" | sed -n '2,10p' | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -u) UNITS="$2"; shift 2 ;;
    --restart) DO_RESTART=1; shift ;;
    -h) usage 0 ;;
    *) echo "Unknown argument: $1" >&2; usage 1 ;;
  esac
done

[[ -n "$UNITS" ]] || { echo "Error: -u <unit1,unit2,...> is required" >&2; usage 1; }

IFS=',' read -ra UNIT_LIST <<< "$UNITS"
UNHEALTHY=0

for unit in "${UNIT_LIST[@]}"; do
  if systemctl is-active --quiet "$unit"; then
    echo "OK:      $unit is active"
    continue
  fi

  STATE="$(systemctl is-active "$unit" || true)"
  echo "PROBLEM: $unit is '$STATE'"
  UNHEALTHY=1

  if [[ "$DO_RESTART" -eq 1 ]]; then
    echo "  attempting restart of $unit..."
    if systemctl restart "$unit"; then
      sleep 2
      if systemctl is-active --quiet "$unit"; then
        echo "  restart succeeded, $unit is now active"
      else
        echo "  restart ran but $unit is still not active"
      fi
    else
      echo "  restart command failed for $unit"
    fi
  fi
done

if (( UNHEALTHY )); then
  exit 1
fi

echo "All checked units are healthy."

