#!/usr/bin/env bash
#
# log-cleanup.sh — compress logs older than N days and delete compressed
# logs older than M days, under a given directory.
#
# Usage:
#   ./log-cleanup.sh -d /var/log/myapp [-c 7] [-r 90] [--max-depth 1] [--dry-run]
#
# Options:
#   -d   Log directory to clean (required)
#   -c   Compress plain-text logs older than this many days (default: 7)
#   -r   Delete .log.gz files older than this many days (default: 90)
#   --max-depth  How deep to recurse under -d (default: 1, no recursion)
#   --dry-run   Print what would happen without changing anything
#   -h   Show this help
#
# gzip replaces the file, so a process that still holds the log open keeps
# writing to the unlinked inode and the data goes nowhere. Point this at logs
# nothing is actively writing, or let logrotate handle the live ones.

set -euo pipefail

LOG_DIR=""
COMPRESS_DAYS=7
RETAIN_DAYS=90
DRY_RUN=0
MAXDEPTH=1

usage() {
  grep '^#' "$0" | sed -n '2,12p' | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

need_arg() {
  [[ $# -ge 2 && -n "${2:-}" ]] || { echo "Error: $1 requires an argument" >&2; exit 1; }
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d) need_arg "$@"; LOG_DIR="$2"; shift 2 ;;
    -c) need_arg "$@"; COMPRESS_DAYS="$2"; shift 2 ;;
    -r) need_arg "$@"; RETAIN_DAYS="$2"; shift 2 ;;
    --max-depth) need_arg "$@"; MAXDEPTH="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h) usage 0 ;;
    *) echo "Unknown argument: $1" >&2; usage 1 ;;
  esac
done

[[ -n "$LOG_DIR" ]] || { echo "Error: -d <log dir> is required" >&2; usage 1; }
[[ -d "$LOG_DIR" ]] || { echo "Error: '$LOG_DIR' does not exist" >&2; exit 1; }

# A non-numeric -c or -r used to reach find as "-mtime +abc". find failed
# inside a process substitution, the loop read nothing, and the script reported
# success while quietly cleaning nothing at all.
for pair in "COMPRESS_DAYS:-c" "RETAIN_DAYS:-r" "MAXDEPTH:--max-depth"; do
  var="${pair%%:*}"; flag="${pair##*:}"
  [[ "${!var}" =~ ^[0-9]+$ ]] || { echo "Error: $flag must be a non-negative integer (got '${!var}')" >&2; exit 1; }
done

if (( RETAIN_DAYS < COMPRESS_DAYS )); then
  echo "Warning: -r ($RETAIN_DAYS) is below -c ($COMPRESS_DAYS); logs will be deleted about as fast as they are compressed." >&2
fi

# One unwritable file must not stop the rest of the cleanup: a stale .gz left
# by an earlier run would otherwise abort every later file and let the disk
# keep filling. Failures are counted and reported at the end.
rc=0

show() { printf '%q ' "$@"; printf '\n'; }

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[dry-run] '
    show "$@"
    return 0
  fi
  show "$@"
  if ! "$@"; then
    echo "  ! failed on ${*: -1}" >&2
    rc=1
  fi
}

echo "Compressing .log files older than $COMPRESS_DAYS day(s) in $LOG_DIR (depth $MAXDEPTH)..."
while IFS= read -r -d '' f; do
  run gzip "$f"
done < <(find "$LOG_DIR" -maxdepth "$MAXDEPTH" -xdev -type f -name "*.log" -mtime "+$COMPRESS_DAYS" -print0)

# Only .log.gz, so this cannot reach into archives some other tool put here.
# The old pattern was a bare *.gz.
echo "Deleting .log.gz files older than $RETAIN_DAYS day(s) in $LOG_DIR (depth $MAXDEPTH)..."
while IFS= read -r -d '' f; do
  run rm -f -- "$f"
done < <(find "$LOG_DIR" -maxdepth "$MAXDEPTH" -xdev -type f -name "*.log.gz" -mtime "+$RETAIN_DAYS" -print0)

if (( rc != 0 )); then
  echo "Done, with one or more failures." >&2
else
  echo "Done."
fi
exit "$rc"
