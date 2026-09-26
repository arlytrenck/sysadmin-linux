#!/usr/bin/env bash
#
# process-watchdog.sh — flag runaway (high CPU/mem) and zombie processes.
#
# Read-only by default. Zombie processes are only reported, never signaled
# (a zombie is already dead — it can't be killed, only reaped by its
# parent). Runaway processes above the CPU/mem thresholds can optionally
# be sent SIGTERM with -k.
#
# ps reports %CPU as CPU time divided by the process's whole lifetime, so a
# process that has just started and spent a moment busy looks pinned at
# 100%. Processes younger than -a seconds are therefore ignored, or -k would
# terminate anything that happened to start while this script was looking.
# -k also never signals init, kernel threads, this script or its parent, or
# the services on the protected list below.
#
# Usage: ./process-watchdog.sh [-c cpu_pct] [-m mem_pct] [-a min_age_sec] [-k]
#   -c   CPU% threshold to flag a process (default: 90)
#   -m   memory% threshold to flag a process (default: 80)
#   -a   ignore processes younger than this many seconds (default: 60)
#   -k   send SIGTERM to processes over threshold (default: report only)
#
# Protected from -k (still reported): systemd, init, sshd, dockerd,
# containerd, containerd-shim, kubelet, dbus-daemon, NetworkManager,
# systemd-journal, systemd-logind, cron, crond.
#
# Exit codes:
#   0  nothing flagged
#   1  at least one category flagged
#
set -euo pipefail

usage() { sed -n '2,/^[^#]/p' "$0" | sed '1{/^#$/d;}; $d; s/^# \{0,1\}//'; exit "${1:-0}"; }

CPU_THRESHOLD=90
MEM_THRESHOLD=80
MIN_AGE=60
KILL=0

while getopts "c:m:a:kh" opt; do
  case "$opt" in
    c) CPU_THRESHOLD=$OPTARG ;;
    m) MEM_THRESHOLD=$OPTARG ;;
    a) MIN_AGE=$OPTARG ;;
    k) KILL=1 ;;
    h) usage 0 ;;
    *) usage 1 ;;
  esac
done

case "$MIN_AGE" in ''|*[!0-9]*) echo "-a must be a whole number of seconds (got '$MIN_AGE')" >&2; exit 1 ;; esac

PROTECTED=" systemd init sshd dockerd containerd containerd-shim kubelet dbus-daemon NetworkManager systemd-journal systemd-logind cron crond "

flagged=0

# Send SIGTERM to every process listed on stdin (pid ppid %cpu %mem etimes
# comm), except the ones that must never be signaled.
terminate() {
  local pid ppid _cpu _mem _age comm
  while read -r pid ppid _cpu _mem _age comm; do
    if [ "$pid" -le 2 ] || [ "$ppid" -eq 2 ] || [ "$pid" -eq $$ ] || [ "$pid" -eq "$PPID" ]; then
      echo "  Skipping PID $pid ($comm): init, kernel thread, or this script's own process"
    elif [[ "$PROTECTED" == *" $comm "* ]]; then
      echo "  Skipping PID $pid ($comm): protected service"
    else
      echo "  Sending SIGTERM to PID $pid ($comm)"
      kill -TERM "$pid" 2>/dev/null || true
    fi
  done
}

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
echo "=== Processes over ${CPU_THRESHOLD}% CPU (running at least ${MIN_AGE}s) ==="
over_cpu=$(ps -eo pid,ppid,%cpu,%mem,etimes,comm --sort=-%cpu | awk -v t="$CPU_THRESHOLD" -v a="$MIN_AGE" 'NR>1 && $3+0 > t && $5+0 >= a')
if [ -z "$over_cpu" ]; then
  echo "None found."
else
  echo "PID   PPID  %CPU  %MEM  AGE(s)  COMM"
  echo "$over_cpu"
  flagged=$((flagged+1))
  if [ "$KILL" -eq 1 ]; then
    echo "$over_cpu" | terminate
  fi
fi

echo ""
echo "=== Processes over ${MEM_THRESHOLD}% memory (running at least ${MIN_AGE}s) ==="
over_mem=$(ps -eo pid,ppid,%cpu,%mem,etimes,comm --sort=-%mem | awk -v t="$MEM_THRESHOLD" -v a="$MIN_AGE" 'NR>1 && $4+0 > t && $5+0 >= a')
if [ -z "$over_mem" ]; then
  echo "None found."
else
  echo "PID   PPID  %CPU  %MEM  AGE(s)  COMM"
  echo "$over_mem"
  flagged=$((flagged+1))
  if [ "$KILL" -eq 1 ]; then
    echo "$over_mem" | terminate
  fi
fi

echo ""
if [ "$flagged" -eq 0 ]; then
  echo "Nothing flagged."
  exit 0
fi
echo "$flagged category/ies flagged above."
exit 1
