#!/usr/bin/env bash
#
# process-watchdog.sh — flag runaway (high CPU/mem) and zombie processes.
#
# Read-only by default; with -k it will send SIGTERM to zombie parents'
# reap trigger is not attempted (zombies can't be killed directly — only
# reaped by their parent), but runaway processes above threshold can
# optionally be signaled with -k.
#
# Usage: ./process-watchdog.sh [-c cpu_pct] [-m mem_pct] [-k]
#   -c   CPU% threshold to flag a process (default: 90)
#   -m   memory% threshold to flag a process (default: 80)
#   -k   send SIGTERM to processes over threshold (default: report only)
#
set -euo pipefail

CPU_THRESHOLD=90
MEM_THRESHOLD=80
KILL=0

while getopts "c:m:kh" opt; do
  case "$opt" in
    c) CPU_THRESHOLD=$OPTARG ;;
    m) MEM_THRESHOLD=$OPTARG ;;
    k) KILL=1 ;;
    h) echo "Usage: $0 [-c cpu_pct] [-m mem_pct] [-k]"; exit 0 ;;
    *) echo "Usage: $0 [-c cpu_pct] [-m mem_pct] [-k]"; exit 1 ;;
  esac
done

flagged=0

echo "=== Zombie processes ==="
zombies=$(ps -eo pid,ppid,stat,comm | awk '$3 ~ /^Z/')
if [ -z "$zombies" ]; then
  echo "None found."
else
  echo "PID   PPID  STAT  COMM"
  echo "$zombies"
  echo ""
  echo "Zombies can't be killed directly — they're already dead; only their"
  echo "parent process (PPID above) can reap them by calling wait(). If a"
  echo "parent accumulates many zombies, it likely has a bug and may need"
  echo "to be restarted."
  flagged=$((flagged+1))
fi

echo ""
echo "=== Processes over ${CPU_THRESHOLD}% CPU ==="
over_cpu=$(ps -eo pid,ppid,%cpu,%mem,comm --sort=-%cpu | awk -v t="$CPU_THRESHOLD" 'NR>1 && $3+0 > t')
if [ -z "$over_cpu" ]; then
  echo "None found."
else
  echo "PID   PPID  %CPU  %MEM  COMM"
  echo "$over_cpu"
  flagged=$((flagged+1))
  if [ "$KILL" -eq 1 ]; then
    echo "$over_cpu" | awk '{print $1}' | while read -r pid; do
      echo "  Sending SIGTERM to PID $pid"
      kill -TERM "$pid" 2>/dev/null || true
    done
  fi
fi

echo ""
echo "=== Processes over ${MEM_THRESHOLD}% memory ==="
over_mem=$(ps -eo pid,ppid,%cpu,%mem,comm --sort=-%mem | awk -v t="$MEM_THRESHOLD" 'NR>1 && $4+0 > t')
if [ -z "$over_mem" ]; then
  echo "None found."
else
  echo "PID   PPID  %CPU  %MEM  COMM"
  echo "$over_mem"
  flagged=$((flagged+1))
  if [ "$KILL" -eq 1 ]; then
    echo "$over_mem" | awk '{print $1}' | while read -r pid; do
      echo "  Sending SIGTERM to PID $pid"
      kill -TERM "$pid" 2>/dev/null || true
    done
  fi
fi

echo ""
[ "$flagged" -eq 0 ] && echo "Nothing flagged." || echo "$flagged category/ies flagged above."

exit 0
