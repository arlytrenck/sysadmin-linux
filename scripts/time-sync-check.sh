#!/usr/bin/env bash
#
# time-sync-check.sh — confirm the host's clock is synchronized and report
# the current offset, whichever time daemon is in use (chrony,
# systemd-timesyncd, or ntpd). Clock drift quietly breaks TLS validation,
# Kerberos, and cross-host log correlation long before anyone notices.
#
# Usage:
#   ./time-sync-check.sh [-t OFFSET_MS]
#
# Options:
#   -t   Warn if the reported offset exceeds this many milliseconds
#        (default 500)
#   -h   Show this help
#
# Exit codes:
#   0 - synchronized and within the offset threshold
#   1 - not synchronized, or offset exceeds the threshold
#   2 - no supported time daemon found / usage error

set -uo pipefail

THRESHOLD_MS=500

usage() {
  grep '^#' "$0" | sed -n '2,15p' | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while getopts ":t:h" opt; do
  case "$opt" in
    t) THRESHOLD_MS="$OPTARG" ;;
    h) usage 0 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage 2 ;;
    :) echo "Option -$OPTARG requires an argument" >&2; usage 2 ;;
  esac
done

flagged=0
found=0

if command -v chronyc >/dev/null 2>&1 && chronyc tracking >/dev/null 2>&1; then
  found=1
  echo "=== chrony ==="
  chronyc tracking
  offset_s="$(chronyc tracking | awk -F': ' '/Last offset/ {print $2}' | awk '{print $1}')"
  offset_ms="$(awk -v s="$offset_s" 'BEGIN { v = s < 0 ? -s : s; printf "%d", v * 1000 }')"
  leap="$(chronyc tracking | awk -F': ' '/Leap status/ {print $2}')"
  echo "Offset: ${offset_ms}ms (threshold ${THRESHOLD_MS}ms), leap status: $leap"
  if [[ "$leap" != "Normal" ]]; then
    echo "FLAG: leap status is '$leap', not 'Normal'"
    flagged=1
  fi
  if (( offset_ms >= THRESHOLD_MS )); then
    echo "FLAG: offset ${offset_ms}ms exceeds threshold ${THRESHOLD_MS}ms"
    flagged=1
  fi
elif command -v timedatectl >/dev/null 2>&1 && timedatectl show >/dev/null 2>&1; then
  found=1
  echo "=== systemd-timesyncd ==="
  timedatectl status
  synced="$(timedatectl show -p NTPSynchronized --value 2>/dev/null)"
  if [[ "$synced" != "yes" ]]; then
    echo "FLAG: NTPSynchronized=$synced"
    flagged=1
  fi
elif command -v ntpq >/dev/null 2>&1 && ntpq -p >/dev/null 2>&1; then
  found=1
  echo "=== ntpd ==="
  ntpq -p
  offset_ms="$(ntpq -pn 2>/dev/null | awk '$1 ~ /^\*/ {print ($9 < 0 ? -$9 : $9); exit}')"
  if [[ -z "$offset_ms" ]]; then
    echo "FLAG: no synchronized peer (no '*' line in ntpq -p)"
    flagged=1
  else
    offset_ms_int="${offset_ms%%.*}"
    echo "Offset: ${offset_ms}ms (threshold ${THRESHOLD_MS}ms)"
    if (( offset_ms_int >= THRESHOLD_MS )); then
      echo "FLAG: offset ${offset_ms}ms exceeds threshold ${THRESHOLD_MS}ms"
      flagged=1
    fi
  fi
fi

if (( ! found )); then
  echo "No supported time daemon found (chrony, systemd-timesyncd, ntpd)." >&2
  exit 2
fi

echo
if (( flagged )); then
  echo "RESULT: time sync problem detected."
  exit 1
fi
echo "RESULT: synchronized and within threshold."
