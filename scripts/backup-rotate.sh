#!/usr/bin/env bash
#
# backup-rotate.sh — tar up a directory, timestamp it, and prune old backups
# beyond a retention count.
#
# Usage:
#   ./backup-rotate.sh -s /path/to/source -d /path/to/backup-dir [-k 7]
#
# Options:
#   -s   Source directory to back up (required)
#   -d   Destination directory to store archives (required)
#   -k   Number of archives to keep (default: 7)
#   -h   Show this help
#
# Exits non-zero on any failure. Intended to be run from cron/systemd timer.

set -euo pipefail

KEEP=7
SRC=""
DEST=""

usage() {
  grep '^#' "$0" | sed -n '2,15p' | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while getopts ":s:d:k:h" opt; do
  case "$opt" in
    s) SRC="$OPTARG" ;;
    d) DEST="$OPTARG" ;;
    k) KEEP="$OPTARG" ;;
    h) usage 0 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage 1 ;;
    :) echo "Option -$OPTARG requires an argument" >&2; usage 1 ;;
  esac
done

if [[ -z "$SRC" || -z "$DEST" ]]; then
  echo "Error: -s and -d are required" >&2
  usage 1
fi

if [[ ! -d "$SRC" ]]; then
  echo "Error: source directory '$SRC' does not exist" >&2
  exit 1
fi

mkdir -p "$DEST"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BASENAME="$(basename "$SRC")"
ARCHIVE="${DEST%/}/${BASENAME}-${TIMESTAMP}.tar.gz"

echo "Backing up '$SRC' to '$ARCHIVE'..."
tar -czf "$ARCHIVE" -C "$(dirname "$SRC")" "$BASENAME"
echo "Backup complete: $(du -h "$ARCHIVE" | cut -f1)"

# Rotate: keep only the newest $KEEP archives for this basename.
mapfile -t OLD_ARCHIVES < <(
  find "$DEST" -maxdepth 1 -type f -name "${BASENAME}-*.tar.gz" \
    | sort -r \
    | tail -n +$((KEEP + 1))
)

if ((${#OLD_ARCHIVES[@]} > 0)); then
  echo "Pruning ${#OLD_ARCHIVES[@]} old archive(s) beyond retention of $KEEP:"
  for f in "${OLD_ARCHIVES[@]}"; do
    echo "  removing $f"
    rm -f "$f"
  done
else
  echo "Nothing to prune (retention: $KEEP)."
fi

echo "Done."

