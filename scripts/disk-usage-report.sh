#!/usr/bin/env bash
#
# disk-usage-report.sh — report filesystem usage and the largest directories
# under a given path, and exit non-zero if any filesystem exceeds a
# threshold (useful for cron + alerting).
#
# Usage:
#   ./disk-usage-report.sh [-p /path/to/scan] [-n 10] [-t 90]
#
# Options:
#   -p   Directory to scan for largest subdirectories (default: /)
#   -n   Number of top consumers to show (default: 10)
#   -t   Threshold percent that triggers a non-zero exit (default: 90)
#   -h   Show this help

set -euo pipefail

SCAN_PATH="/"
TOP_N=10
THRESHOLD=90

usage() {
  grep '^#' "$0" | sed -n '2,12p' | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while getopts ":p:n:t:h" opt; do
  case "$opt" in
    p) SCAN_PATH="$OPTARG" ;;
    n) TOP_N="$OPTARG" ;;
    t) THRESHOLD="$OPTARG" ;;
    h) usage 0 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage 1 ;;
    :) echo "Option -$OPTARG requires an argument" >&2; usage 1 ;;
  esac
done

echo "=== Filesystem usage ==="
df -hP | awk 'NR==1 || $NF !~ /^\/(dev|proc|sys|run)/'

echo
echo "=== Top $TOP_N largest directories under $SCAN_PATH ==="
du -x -h --max-depth=2 "$SCAN_PATH" 2>/dev/null \
  | sort -rh \
  | head -n "$TOP_N"

echo
echo "=== Threshold check (>${THRESHOLD}%) ==="
OVER=0
while read -r line; do
  PCT="$(echo "$line" | awk '{print $5}' | tr -d '%')"
  MOUNT="$(echo "$line" | awk '{print $6}')"
  if [[ "$PCT" =~ ^[0-9]+$ ]] && (( PCT >= THRESHOLD )); then
    echo "WARNING: $MOUNT is at ${PCT}% (threshold: ${THRESHOLD}%)"
    OVER=1
  fi
done < <(df -hP | tail -n +2)

if (( OVER )); then
  echo "One or more filesystems exceeded the threshold."
  exit 2
fi

echo "All filesystems below threshold."

