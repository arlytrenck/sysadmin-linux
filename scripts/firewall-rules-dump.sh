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
# Must be run as root: without it every backend prints a permission error,
# and that error used to be saved as the "ruleset" (and diffed next time).
#
# The dump is written to be diffable. Packet and byte counters are zeroed
# (nft) or left out (iptables -S), because they change on every packet and
# made every comparison against a baseline report the whole ruleset as
# changed. A baseline taken with an older version will differ once.

set -uo pipefail

OUT_DIR="."
BASELINE=""

usage() { sed -n '2,/^[^#]/p' "$0" | sed '1{/^#$/d;}; $d; s/^# \{0,1\}//'; exit "${1:-0}"; }

while getopts ":o:d:h" opt; do
  case "$opt" in
    o) OUT_DIR="$OPTARG" ;;
    d) BASELINE="$OPTARG" ;;
    h) usage 0 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage 1 ;;
    :) echo "Option -$OPTARG requires an argument" >&2; usage 1 ;;
  esac
done

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Error: reading the firewall ruleset needs root — re-run with sudo." >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname)"
OUT_FILE="${OUT_DIR%/}/firewall-${HOSTNAME_SHORT}-${TIMESTAMP}.txt"

{
  if command -v nft &>/dev/null && nft list ruleset &>/dev/null; then
    echo "# Backend: nftables"
    nft list ruleset | sed -E 's/\b(packets|bytes) [0-9]+/\1 0/g'
  elif command -v ufw &>/dev/null && ufw status verbose &>/dev/null 2>&1; then
    echo "# Backend: ufw"
    ufw status verbose
    echo
    echo "# Underlying iptables rules"
    iptables -S 2>/dev/null
  elif command -v iptables &>/dev/null; then
    echo "# Backend: iptables"
    iptables -S
    echo
    echo "# ip6tables"
    ip6tables -S 2>/dev/null
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

