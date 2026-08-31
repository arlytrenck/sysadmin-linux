#!/usr/bin/env bash
#
# raid-smart-health-check.sh — check mdadm RAID array status and SMART
# health for underlying block devices. Read-only; exits non-zero if
# anything looks degraded or failing, so it's safe to wire into a
# monitoring cron job.
#
# Usage: ./raid-smart-health-check.sh
#
# Requires: mdadm (if using Linux software RAID), smartmontools (smartctl)
#
set -uo pipefail

worst=0

echo "=== mdadm RAID array status ==="
if command -v mdadm >/dev/null 2>&1 && [ -r /proc/mdstat ]; then
  arrays=$(awk '/^md/{print $1}' /proc/mdstat)
  if [ -z "$arrays" ]; then
    echo "No active md arrays found."
  fi
  for array in $arrays; do
    detail=$(mdadm --detail "/dev/$array" 2>/dev/null) || continue
    state=$(echo "$detail" | awk -F': ' '/State :/{print $2; exit}')
    echo "$array: $state"
    case "$state" in
      *degraded*|*failed*|*resyncing* )
        echo "  [WARN] $array reports: $state"
        [ "$worst" -lt 1 ] && worst=1
        case "$state" in *degraded*|*failed*) worst=2 ;; esac
        ;;
    esac
  done
else
  echo "mdadm not available or no /proc/mdstat — skipping software RAID check."
fi

echo ""
echo "=== SMART health per block device ==="
if command -v smartctl >/dev/null 2>&1; then
  for dev in /dev/sd? /dev/nvme?n1; do
    [ -e "$dev" ] || continue
    health=$(smartctl -H "$dev" 2>/dev/null | awk -F': ' '/overall-health|SMART Health Status/{print $2; exit}')
    health=${health:-unknown}
    echo "$dev: $health"
    if [ "$health" != "PASSED" ] && [ "$health" != "OK" ] && [ "$health" != "unknown" ]; then
      echo "  [FAIL] $dev SMART health: $health"
      worst=2
    fi

    # Surface a couple of the most predictive SMART attributes, if readable
    smartctl -A "$dev" 2>/dev/null | awk '
      /Reallocated_Sector_Ct|Current_Pending_Sector|Offline_Uncorrectable/ {
        if ($10+0 > 0) print "  [WARN] " $2 " = " $10
      }'
  done
else
  echo "smartctl not found — install smartmontools to enable this check."
fi

echo ""
case "$worst" in
  0) echo "Result: OK" ;;
  1) echo "Result: WARNING — review output above" ;;
  2) echo "Result: CRITICAL — review output above" ;;
esac

exit "$worst"
