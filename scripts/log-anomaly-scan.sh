#!/usr/bin/env bash
#
# log-anomaly-scan.sh - flag an unusual spike in error/warning-level log
#   lines over the last N minutes, compared to a trailing baseline window.
#
# Rather than grepping for specific known-bad strings, this compares the
# *rate* of error-level lines in a recent window against an earlier
# baseline window of the same length, so it catches problems you didn't
# think to grep for in advance. Works against journald when available,
# falling back to /var/log/syslog or /var/log/messages.
#
# Usage: ./log-anomaly-scan.sh [-w minutes] [-m multiplier] [-u unit]
#   -w  window size in minutes for both "recent" and "baseline" (default: 15)
#   -m  flag if recent-rate >= multiplier * baseline-rate (default: 3)
#   -u  restrict journald query to a single systemd unit (optional)
#
# Exit codes: 0 = no anomaly, 1 = anomaly flagged, 2 = no log source found

set -uo pipefail

window_min=15
multiplier=3
unit=""

usage() {
    echo "Usage: $0 [-w minutes] [-m multiplier] [-u unit]"
    exit 0
}

while getopts "w:m:u:h" opt; do
    case "$opt" in
        w) window_min="$OPTARG" ;;
        m) multiplier="$OPTARG" ;;
        u) unit="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

count_journald() {
    local since="$1" until="$2"
    local args=(--no-pager -p err..emerg --since "$since" --until "$until")
    [[ -n "$unit" ]] && args+=(-u "$unit")
    journalctl "${args[@]}" 2>/dev/null | wc -l
}

count_flatfile() {
    local logfile="$1"
    # Best-effort: count lines containing common error markers within the
    # file's tail; flat-file timestamp parsing is inherently approximate,
    # so this doesn't try to slice by time window the way journald does.
    grep -Eic '\berror\b|\bfail(ed|ure)?\b|\bcrit(ical)?\b|\bpanic\b' "$logfile" 2>/dev/null
}

now_epoch=$(date +%s)
recent_since_epoch=$(( now_epoch - window_min * 60 ))
baseline_since_epoch=$(( now_epoch - 2 * window_min * 60 ))

now_iso=$(date -d "@$now_epoch" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$now_epoch" '+%Y-%m-%d %H:%M:%S')
recent_since_iso=$(date -d "@$recent_since_epoch" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$recent_since_epoch" '+%Y-%m-%d %H:%M:%S')
baseline_since_iso=$(date -d "@$baseline_since_epoch" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$baseline_since_epoch" '+%Y-%m-%d %H:%M:%S')

if command -v journalctl >/dev/null 2>&1 && [[ -d /run/systemd/journal ]]; then
    source="journald"
    recent_count=$(count_journald "$recent_since_iso" "$now_iso")
    baseline_count=$(count_journald "$baseline_since_iso" "$recent_since_iso")
elif [[ -r /var/log/syslog ]]; then
    source="/var/log/syslog (approximate - no time-window slicing)"
    recent_count=$(count_flatfile /var/log/syslog)
    baseline_count=""
elif [[ -r /var/log/messages ]]; then
    source="/var/log/messages (approximate - no time-window slicing)"
    recent_count=$(count_flatfile /var/log/messages)
    baseline_count=""
else
    echo "No usable log source found (no journald, /var/log/syslog, or /var/log/messages)."
    exit 2
fi

echo "Log source: $source"
echo "Recent window:   last ${window_min}m -> $recent_count error-level lines"

if [[ -n "$baseline_count" ]]; then
    echo "Baseline window: prior ${window_min}m -> $baseline_count error-level lines"
    # Avoid divide-by-zero; treat a zero baseline with any recent errors as
    # a spike once recent_count passes a small floor, so a quiet system
    # isn't flagged for going from 0 to 1.
    floor=5
    if [[ "$baseline_count" -eq 0 ]]; then
        if [[ "$recent_count" -ge "$floor" ]]; then
            echo "ANOMALY: baseline was 0 errors, recent window has $recent_count (>= floor of $floor)."
            exit 1
        else
            echo "OK: baseline was 0, recent count $recent_count is below the $floor floor."
            exit 0
        fi
    fi
    threshold=$(( baseline_count * multiplier ))
    if [[ "$recent_count" -ge "$threshold" ]]; then
        echo "ANOMALY: recent count $recent_count >= ${multiplier}x baseline ($threshold)."
        exit 1
    else
        echo "OK: recent count $recent_count is below ${multiplier}x baseline ($threshold)."
        exit 0
    fi
else
    echo "No baseline available from a flat-file source; recent count reported for manual review."
    exit 0
fi
