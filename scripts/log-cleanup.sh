#!/usr/bin/env bash
#
# log-cleanup.sh — compress logs older than N days and delete compressed
# logs older than M days, under a given directory.
#
# Usage:
#   ./log-cleanup.sh -d /var/log/myapp [-c 7] [-r 90] [--dry-run]
#
# Options:
#   -d   Log directory to clean (required)
#   -c   Compress plain-text logs older than this many days (default: 7)
#   -r   Delete .gz logs older than this many days (default: 90)
#   --dry-run   Print what would happen without changing anything
#   -h   Show this help

set -euo pipefail

LOG_DIR=""
COMPRESS_DAYS=7
RETAIN_DAYS=90
DRY_RUN=0

usage() {
  grep '^#' "$0" | sed -n '2,12p' | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d) LOG_DIR="$2"; shift 2 ;;
    -c) COMPRESS_DAYS="$2"; shift 2 ;;
    -r) RETAIN_DAYS="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h) usage 0 ;;
    *) echo "Unknown argument: $1" >&2; usage 1 ;;
  esac
done

[[ -n "$LOG_DIR" ]] || { echo "Error: -d <log dir> is required" >&2; usage 1; }
[[ -d "$LOG_DIR" ]] || { echo "Error: '$LOG_DIR' does not exist" >&2; exit 1; }

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] $*"
  else
    echo "$*"
    "$@"
  fi
}

echo "Compressing .log files older than $COMPRESS_DAYS day(s) in $LOG_DIR..."
while IFS= read -r -d '' f; do
  run gzip "$f"
done < <(find "$LOG_DIR" -type f -name "*.log" -mtime "+$COMPRESS_DAYS" -print0)

echo "Deleting .gz files older than $RETAIN_DAYS day(s) in $LOG_DIR..."
while IFS= read -r -d '' f; do
  run rm -f "$f"
done < <(find "$LOG_DIR" -type f -name "*.gz" -mtime "+$RETAIN_DAYS" -print0)

echo "Done."

