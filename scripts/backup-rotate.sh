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

usage() { sed -n '2,/^[^#]/p' "$0" | sed '1{/^#$/d;}; $d; s/^# \{0,1\}//'; exit "${1:-0}"; }

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

# An unvalidated -k used to reach the arithmetic below, where 'set -u' aborted
# the subshell. The prune found nothing, the script still printed "Nothing to
# prune" and exited 0, and retention quietly stopped for as long as the cron
# entry stayed broken.
if [[ ! "$KEEP" =~ ^[0-9]+$ ]] || (( KEEP < 1 )); then
  echo "Error: -k must be a positive integer (got '$KEEP')" >&2
  exit 1
fi

if [[ ! -d "$SRC" ]]; then
  echo "Error: source directory '$SRC' does not exist" >&2
  exit 1
fi

mkdir -p "$DEST"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BASENAME="$(basename "$SRC")"
ARCHIVE="${DEST%/}/${BASENAME}-${TIMESTAMP}.tar.gz"

# Writing the archive into its own source is a way to fill a disk.
SRC_REAL="$(readlink -f "$SRC")"
DEST_REAL="$(readlink -f "$DEST")"
if [[ "$DEST_REAL" == "$SRC_REAL" || "$DEST_REAL" == "$SRC_REAL"/* ]]; then
  echo "Error: destination '$DEST' is inside source '$SRC'" >&2
  exit 1
fi

echo "Backing up '$SRC' to '$ARCHIVE'..."
tar -czf "$ARCHIVE" -C "$(dirname "$SRC")" "$BASENAME"
echo "Backup complete: $(du -h "$ARCHIVE" | cut -f1)"

# Rotate: keep only the newest $KEEP archives for this basename.
#
# Matching is done on the exact "<basename>-YYYYmmdd-HHMMSS.tar.gz" shape this
# script writes. The old pattern was a bare "${BASENAME}-*", which also matched
# sibling backups whose name merely starts with the same prefix: backing up
# /srv/app pruned /srv/app-data's archives, and since "app-data-..." sorts
# above "app-2026...", it deleted the archive it had just written.
#
# The filtering is done in bash rather than by find, so a basename containing
# a glob or regex metacharacter is compared literally.
ALL_ARCHIVES=()
while IFS= read -r -d '' f; do
  name="${f##*/}"
  suffix="${name#"${BASENAME}-"}"
  [[ "$suffix" == "$name" ]] && continue                 # prefix did not match
  [[ "$suffix" =~ ^[0-9]{8}-[0-9]{6}\.tar\.gz$ ]] || continue
  ALL_ARCHIVES+=("$f")
done < <(find "$DEST" -maxdepth 1 -type f -print0)

mapfile -t OLD_ARCHIVES < <(printf '%s\n' "${ALL_ARCHIVES[@]:-}" | grep -v '^$' | sort -r | tail -n +$((KEEP + 1)))

if ((${#OLD_ARCHIVES[@]} > 0)); then
  echo "Pruning ${#OLD_ARCHIVES[@]} old archive(s) beyond retention of $KEEP:"
  for f in "${OLD_ARCHIVES[@]}"; do
    echo "  removing $f"
    rm -f -- "$f"
  done
else
  echo "Nothing to prune (retention: $KEEP)."
fi

echo "Done."
