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

usage() { sed -n '2,/^[^#]/p' "$0" | sed '1{/^#$/d;}; $d; s/^# \{0,1\}//'; exit "${1:-0}"; }

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

# Pseudo and read-only image filesystems are skipped everywhere below: snap
# and loop mounts (squashfs) are always 100% full by construction, so leaving
# them in meant the threshold check alarmed on every Ubuntu host with snaps.
DF_EXCLUDES=(-x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs)

echo "=== Filesystem usage ==="
df -hP "${DF_EXCLUDES[@]}"

echo
echo "=== Top $TOP_N largest directories under $SCAN_PATH ==="
# `|| true`: du exits 1 on any unreadable directory (every run that isn't
# root), and head can close the pipe early; under pipefail either would end
# the script before the threshold check below.
du -x -h --max-depth=2 "$SCAN_PATH" 2>/dev/null \
  | sort -rh \
  | sed -n "1,${TOP_N}p" || true

echo
echo "=== Threshold check (>=${THRESHOLD}%) ==="
OVER=0
# Capacity is field 5; the mount point is everything from field 6 on, which
# keeps mount points containing spaces intact.
while read -r PCT MOUNT; do
  PCT="${PCT%\%}"
  if [[ "$PCT" =~ ^[0-9]+$ ]] && (( PCT >= THRESHOLD )); then
    echo "WARNING: $MOUNT is at ${PCT}% (threshold: ${THRESHOLD}%)"
    OVER=1
  fi
done < <(df -hP "${DF_EXCLUDES[@]}" | awk 'NR > 1 {m=$6; for (i=7;i<=NF;i++) m=m " " $i; print $5, m}')

if (( OVER )); then
  echo "One or more filesystems exceeded the threshold."
  exit 2
fi

echo "All filesystems below threshold."

