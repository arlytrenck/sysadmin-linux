#!/usr/bin/env bash
#
# age-backup.sh — take a file, directory, or the output of a command, compress
#   it, encrypt it with age, keep the last N copies, and write a checksum
#   manifest. Meant for the "one encrypted, off-host copy" leg of a 3-2-1
#   backup — pair it with backup-rotate.sh for the local copies.
#
# Usage:
#   ./age-backup.sh -n NAME -o DIR -r RECIPIENTS [-k KEEP] (-s PATH | -c "CMD")
#
# Options:
#   -n NAME   Base name for the artifact (e.g. "postgres", "etc").
#   -o DIR    Output directory for the encrypted artifacts.
#   -r FILE   age recipients file (one `age1...`/`ssh-ed25519 ...` per line).
#             Or set AGE_RECIPIENTS_FILE in the environment.
#   -s PATH   Source file or directory to back up.
#   -c CMD    Instead of -s, run CMD and encrypt its stdout (e.g. a DB dump).
#   -k KEEP   Timestamped copies to retain (default: 14).
#   -h        Show this help.
#
# Output: DIR/NAME-<UTC timestamp>.tar.gz.age  (+ a NAME-latest.tar.gz.age copy
#   and a refreshed SHA256SUMS). A single file/-c stream is stored as
#   NAME-<ts>.gz.age instead of a tarball.
#
# Refuses to run if `age` or the recipients file is missing — it will never
# write an unencrypted artifact.
#
# Exit codes: 0 = OK, 1 = backup failed, 2 = usage / missing prerequisite

set -uo pipefail

NAME="" ; OUT="" ; RECIP="${AGE_RECIPIENTS_FILE:-}" ; SRC="" ; CMD="" ; KEEP=14
usage() { grep -E '^#( |$)' "$0" | sed '1d; s/^# \{0,1\}//'; exit "${1:-0}"; }

while getopts ":n:o:r:s:c:k:h" opt; do
  case "$opt" in
    n) NAME="$OPTARG" ;;
    o) OUT="$OPTARG" ;;
    r) RECIP="$OPTARG" ;;
    s) SRC="$OPTARG" ;;
    c) CMD="$OPTARG" ;;
    k) KEEP="$OPTARG" ;;
    h) usage 0 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage 2 ;;
    :) echo "Option -$OPTARG requires an argument" >&2; usage 2 ;;
  esac
done

command -v age >/dev/null 2>&1 || { echo "age is not installed — refusing to write an unencrypted backup." >&2; exit 2; }
[ -n "$NAME" ] || { echo "-n NAME is required." >&2; usage 2; }
[ -n "$OUT" ]  || { echo "-o DIR is required." >&2; usage 2; }
[ -n "$RECIP" ] && [ -r "$RECIP" ] || { echo "-r RECIPIENTS file missing or unreadable." >&2; exit 2; }
if [ -n "$SRC" ] && [ -n "$CMD" ]; then echo "Use -s or -c, not both." >&2; exit 2; fi
if [ -z "$SRC" ] && [ -z "$CMD" ]; then echo "One of -s PATH or -c CMD is required." >&2; usage 2; fi
[ -n "$SRC" ] && [ ! -e "$SRC" ] && { echo "Source not found: $SRC" >&2; exit 2; }
case "$KEEP" in ''|*[!0-9]*) echo "-k must be a number." >&2; exit 2 ;; esac

mkdir -p "$OUT" || exit 2
ts="$(date -u '+%Y%m%d-%H%M%SZ')"

# Build the age recipient args from the file (skip blanks and # comments).
RARGS=()
while IFS= read -r line; do
  [ -n "$line" ] && RARGS+=(-r "$line")
done < <(grep -vE '^\s*(#|$)' "$RECIP")
[ "${#RARGS[@]}" -gt 0 ] || { echo "No recipients parsed from $RECIP" >&2; exit 2; }

if [ -n "$CMD" ]; then
  out="$OUT/$NAME-$ts.gz.age"
  latest="$OUT/$NAME-latest.gz.age"
  if bash -c "$CMD" | gzip | age "${RARGS[@]}" -o "$out"; then
    rc_ok=1
  else
    rc_ok=0
  fi
elif [ -d "$SRC" ]; then
  out="$OUT/$NAME-$ts.tar.gz.age"
  latest="$OUT/$NAME-latest.tar.gz.age"
  if tar -C "$(dirname "$SRC")" -czf - "$(basename "$SRC")" | age "${RARGS[@]}" -o "$out"; then
    rc_ok=1
  else
    rc_ok=0
  fi
else
  out="$OUT/$NAME-$ts.gz.age"
  latest="$OUT/$NAME-latest.gz.age"
  if gzip -c "$SRC" | age "${RARGS[@]}" -o "$out"; then
    rc_ok=1
  else
    rc_ok=0
  fi
fi

if [ "${rc_ok:-0}" -ne 1 ] || [ ! -s "$out" ]; then
  echo "Backup FAILED (pipeline error or empty artifact)." >&2
  rm -f "$out"
  exit 1
fi

cp -f "$out" "$latest"
# prune old timestamped copies for this NAME
find "$OUT" -maxdepth 1 -type f -name "$NAME-*Z.*.age" -printf '%T@ %p\n' \
  | sort -rn | awk -v k="$KEEP" 'NR>k {print $2}' | xargs -r rm -f
( cd "$OUT" && sha256sum ./*.age > SHA256SUMS 2>/dev/null ) || true

echo "OK  $out  ($(du -h "$out" | cut -f1), encrypted to $(( ${#RARGS[@]} / 2 )) recipient(s))"
