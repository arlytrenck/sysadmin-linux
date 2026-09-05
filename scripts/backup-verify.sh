#!/usr/bin/env bash
# backup-verify.sh — assert that backups in a directory exist, are recent, and
# pass a cheap integrity check. Wire into cron; non-zero exit = alert.
#
# Usage:
#   backup-verify.sh -d /path/to/backups [-a MAX_AGE_HOURS] [-g GLOB]
#     -d  directory to check (required)
#     -a  fail if the newest matching file is older than this many hours (default 26)
#     -g  glob for the files that matter (default '*')  e.g. '*.sql.gz.age'
#
# Integrity: *.gz / *.tgz -> gzip -t ; *.zst -> zstd -t ; *.age -> header check ;
# a sibling SHA256SUMS.txt -> sha256sum -c ; otherwise just non-empty + readable.
set -euo pipefail

DIR="" ; MAX_AGE_H=26 ; GLOB='*'
while getopts "d:a:g:h" o; do case "$o" in
  d) DIR=$OPTARG ;; a) MAX_AGE_H=$OPTARG ;; g) GLOB=$OPTARG ;;
  *) sed -n '2,14p' "$0"; exit 2 ;;
esac; done
[ -d "$DIR" ] || { echo "not a directory: $DIR"; exit 2; }

shopt -s nullglob
# shellcheck disable=SC2206 # GLOB is meant to expand; nullglob makes it safe
files=( "$DIR"/$GLOB )
[ "${#files[@]}" -gt 0 ] || { echo "FAIL: no files matching '$GLOB' in $DIR"; exit 1; }

newest=$(ls -1t "${files[@]}" | head -1)
age_h=$(( ( $(date +%s) - $(stat -c %Y "$newest") ) / 3600 ))
echo "newest: $newest  (${age_h}h old, ${#files[@]} files)"
rc=0
[ "$age_h" -gt "$MAX_AGE_H" ] && { echo "FAIL: newest backup is ${age_h}h old (> ${MAX_AGE_H}h)"; rc=1; }

if [ -f "$DIR/SHA256SUMS.txt" ]; then
  ( cd "$DIR" && sha256sum -c --quiet SHA256SUMS.txt ) || { echo "FAIL: sha256sum -c"; rc=1; }
fi

check_one(){
  local f=$1
  [ -s "$f" ] || { echo "FAIL: empty $f"; return 1; }
  case "$f" in
    *.gz|*.tgz) gzip -t "$f" || return 1 ;;
    *.zst)      command -v zstd >/dev/null && { zstd -tq "$f" || return 1; } ;;
    *.age)      head -c 20 "$f" | grep -q 'age-encryption' || { echo "FAIL: not an age file? $f"; return 1; } ;;
  esac
}
check_one "$newest" || rc=1

[ "$rc" -eq 0 ] && echo "OK" || echo "PROBLEMS FOUND"
exit $rc
