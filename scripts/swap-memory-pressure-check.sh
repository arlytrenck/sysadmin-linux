#!/usr/bin/env bash
#
# swap-memory-pressure-check.sh — report memory/swap usage and kernel memory
# pressure, and flag recent OOM kills. Useful for cron + alerting on hosts
# that silently thrash before anyone notices.
#
# Usage:
#   ./swap-memory-pressure-check.sh [-s SWAP_PCT] [-m MEM_PCT] [-p PSI_AVG10]
#
# Options:
#   -s   Warn if swap used exceeds this percent (default 50)
#   -m   Warn if memory used exceeds this percent (default 90)
#   -p   Warn if /proc/pressure/memory "full avg10" exceeds this percent,
#        i.e. tasks stalled waiting on memory (default 10; skipped if the
#        kernel has no PSI support)
#   -h   Show this help
#
# Exit codes: 0 = all clear, 1 = one or more thresholds exceeded or an OOM
# kill was found in the recent journal, 2 = usage error

set -uo pipefail

SWAP_PCT=50
MEM_PCT=90
PSI_PCT=10

usage() {
  grep '^#' "$0" | sed -n '2,17p' | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while getopts ":s:m:p:h" opt; do
  case "$opt" in
    s) SWAP_PCT="$OPTARG" ;;
    m) MEM_PCT="$OPTARG" ;;
    p) PSI_PCT="$OPTARG" ;;
    h) usage 0 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage 2 ;;
    :) echo "Option -$OPTARG requires an argument" >&2; usage 2 ;;
  esac
done

command -v free >/dev/null 2>&1 || { echo "free not found." >&2; exit 2; }

flagged=0

echo "=== Memory ==="
read -r mem_total mem_used < <(free -b | awk '/^Mem:/ {print $2, $3}')
mem_pct=$(( mem_used * 100 / mem_total ))
free -h
echo "Used: ${mem_pct}% (threshold ${MEM_PCT}%)"
if (( mem_pct >= MEM_PCT )); then
  echo "FLAG: memory usage at ${mem_pct}%"
  flagged=1
fi

echo
echo "=== Swap ==="
read -r swap_total swap_used < <(free -b | awk '/^Swap:/ {print $2, $3}')
if [[ "${swap_total:-0}" -gt 0 ]]; then
  swap_pct=$(( swap_used * 100 / swap_total ))
  echo "Used: ${swap_pct}% (threshold ${SWAP_PCT}%)"
  if (( swap_pct >= SWAP_PCT )); then
    echo "FLAG: swap usage at ${swap_pct}%"
    flagged=1
  fi
else
  echo "No swap configured."
fi

echo
echo "=== Memory pressure (PSI) ==="
if [[ -r /proc/pressure/memory ]]; then
  cat /proc/pressure/memory
  full_avg10="$(awk -F'avg10=| ' '/^full/ {print $2}' /proc/pressure/memory)"
  if [[ -n "$full_avg10" ]]; then
    full_avg10_int="${full_avg10%%.*}"
    echo "full avg10: ${full_avg10}% (threshold ${PSI_PCT}%)"
    if (( full_avg10_int >= PSI_PCT )); then
      echo "FLAG: tasks are stalling on memory pressure"
      flagged=1
    fi
  fi
else
  echo "No PSI support (/proc/pressure/memory not present) — skipping."
fi

echo
echo "=== Recent OOM kills ==="
if command -v journalctl >/dev/null 2>&1; then
  oom_lines="$(journalctl -k --since '24 hours ago' 2>/dev/null | grep -iE 'out of memory|oom.?kill' || true)"
else
  oom_lines="$(dmesg 2>/dev/null | grep -iE 'out of memory|oom.?kill' || true)"
fi
if [[ -n "$oom_lines" ]]; then
  echo "$oom_lines"
  echo "FLAG: OOM kill(s) found in the last 24h"
  flagged=1
else
  echo "None found in the last 24h."
fi

echo
if (( flagged )); then
  echo "RESULT: one or more thresholds exceeded."
  exit 1
fi
echo "RESULT: all clear."
