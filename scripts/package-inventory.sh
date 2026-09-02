#!/usr/bin/env bash
#
# package-inventory.sh — dump the installed package list (with versions)
# to a timestamped file, and optionally diff against a previous baseline
# to see what changed. Auto-detects apt/dpkg, dnf/rpm, or yum.
#
# Usage:
#   ./package-inventory.sh [-o /path/to/output-dir] [-d /path/to/baseline.txt]
#
# Options:
#   -o   Directory to write the timestamped inventory file to (default: .)
#   -d   Previous inventory file to diff the new snapshot against
#   -h   Show this help

set -euo pipefail

OUT_DIR="."
BASELINE=""

usage() {
  grep '^#' "$0" | sed -n '2,9p' | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while getopts ":o:d:h" opt; do
  case "$opt" in
    o) OUT_DIR="$OPTARG" ;;
    d) BASELINE="$OPTARG" ;;
    h) usage 0 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage 1 ;;
    :) echo "Option -$OPTARG requires an argument" >&2; usage 1 ;;
  esac
done

mkdir -p "$OUT_DIR"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname)"
OUT_FILE="${OUT_DIR%/}/packages-${HOSTNAME_SHORT}-${TIMESTAMP}.txt"

if command -v dpkg-query &>/dev/null; then
  dpkg-query -W -f='${Package}\t${Version}\n' | sort > "$OUT_FILE"
elif command -v rpm &>/dev/null; then
  rpm -qa --qf '%{NAME}\t%{VERSION}-%{RELEASE}\n' | sort > "$OUT_FILE"
else
  echo "Error: no supported package manager found (dpkg-query, rpm)" >&2
  exit 1
fi

echo "Wrote $(wc -l < "$OUT_FILE") package entries to $OUT_FILE"

if [[ -n "$BASELINE" ]]; then
  if [[ ! -f "$BASELINE" ]]; then
    echo "Error: baseline file '$BASELINE' not found" >&2
    exit 1
  fi
  echo
  echo "=== Diff against $BASELINE ==="
  diff --unchanged-line-format='' --old-line-format='removed: %L' --new-line-format='added:   %L' \
    "$BASELINE" "$OUT_FILE" || true
fi

