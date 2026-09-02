#!/usr/bin/env bash
#
# firewall-rules-dump.sh — dump the active firewall ruleset (nftables,
# iptables, or ufw — whichever is in use) to a timestamped file, for
# backup, review, or diffing against a previous snapshot.
#
# Usage:
#   ./firewall-rules-dump.sh [-o /path/to/output-dir] [-d /path/to/previous-dump.txt]
#
# Options:
#   -o   Directory to write the timestamped dump to (default: .)
#   -d   Previous dump file to diff the new snapshot against
#   -h   Show this help
#
# Must be run with enough privilege to read firewall rules (usually root).

set -uo pipefail

OUT_DIR="."
BASELINE=""

usage() {
  grep '^#' "$0" | sed -n '2,11p' | sed 's/^# \{0,1\}//'
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
OUT_FILE="${OUT_DIR%/}/firewall-${HOSTNAME_SHORT}-${TIMESTAMP}.txt"

{
  if command -v nft &>/dev/null && nft list ruleset &>/dev/null; then
    echo "# Backend: nftables"
    nft list ruleset
  elif command -v ufw &>/dev/null && ufw status verbose &>/dev/null 2>&1; then
    echo "# Backend: ufw"
    ufw status verbose
    echo
    echo "# Underlying iptables rules"
    iptables -L -n -v 2>/dev/null
  elif command -v iptables &>/dev/null; then
    echo "# Backend: iptables"
    iptables -L -n -v
    echo
    echo "# ip6tables"
    ip6tables -L -n -v 2>/dev/null
  else
    echo "# No supported firewall tool found (nft, ufw, iptables)"
  fi
} > "$OUT_FILE" 2>&1

echo "Wrote firewall ruleset to $OUT_FILE"

if [[ -n "$BASELINE" ]]; then
  if [[ ! -f "$BASELINE" ]]; then
    echo "Error: baseline file '$BASELINE' not found" >&2
    exit 1
  fi
  echo
  echo "=== Diff against $BASELINE ==="
  diff -u "$BASELINE" "$OUT_FILE" || true
fi

