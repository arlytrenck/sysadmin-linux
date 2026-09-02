#!/usr/bin/env bash
#
# update-and-patch.sh — wrapper around apt or dnf/yum to update package
# lists, apply upgrades, and log the results with a timestamp. Detects the
# available package manager automatically.
#
# Usage:
#   ./update-and-patch.sh [-l /var/log/patching.log] [--reboot-if-needed]
#
# Options:
#   -l   Log file to append output to (default: /var/log/update-and-patch.log)
#   --reboot-if-needed   Reboot automatically if the OS reports a reboot is required
#   -h   Show this help
#
# Must be run as root (or via sudo).

set -euo pipefail

LOG_FILE="/var/log/update-and-patch.log"
REBOOT_IF_NEEDED=0

usage() {
  grep '^#' "$0" | sed -n '2,13p' | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -l) LOG_FILE="$2"; shift 2 ;;
    --reboot-if-needed) REBOOT_IF_NEEDED=1; shift ;;
    -h) usage 0 ;;
    *) echo "Unknown argument: $1" >&2; usage 1 ;;
  esac
done

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Error: this script must be run as root" >&2
  exit 1
fi

mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "===== $(date -Iseconds) — starting update-and-patch ====="

if command -v apt-get &>/dev/null; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get upgrade -y
  apt-get autoremove -y
  REBOOT_REQUIRED=0
  [[ -f /var/run/reboot-required ]] && REBOOT_REQUIRED=1

elif command -v dnf &>/dev/null; then
  dnf -y makecache
  dnf -y upgrade
  REBOOT_REQUIRED=0
  if command -v needs-restarting &>/dev/null; then
    needs-restarting -r &>/dev/null || REBOOT_REQUIRED=1
  fi

elif command -v yum &>/dev/null; then
  yum -y makecache
  yum -y update
  REBOOT_REQUIRED=0
  if command -v needs-restarting &>/dev/null; then
    needs-restarting -r &>/dev/null || REBOOT_REQUIRED=1
  fi

else
  echo "Error: no supported package manager found (apt-get, dnf, yum)" >&2
  exit 1
fi

echo "===== $(date -Iseconds) — update-and-patch complete ====="

if [[ "$REBOOT_REQUIRED" -eq 1 ]]; then
  echo "A reboot is required to complete updates."
  if [[ "$REBOOT_IF_NEEDED" -eq 1 ]]; then
    echo "Rebooting now as requested (--reboot-if-needed)..."
    reboot
  fi
fi

