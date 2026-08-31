#!/usr/bin/env bash
#
# cert-expiry-check.sh — check TLS certificate expiry for one or more
# host:port targets, or a local PEM file, and warn/fail below a threshold.
#
# Usage:
#   ./cert-expiry-check.sh -t host:port [-t host:port ...] [-w 30] [-c 7]
#   ./cert-expiry-check.sh -f /path/to/cert.pem [-w 30] [-c 7]
#
# Options:
#   -t   host:port to check (repeatable). Default port 443 if omitted.
#   -f   Local PEM certificate file to check instead of a live connection.
#   -w   Warn if expiry is within this many days (default: 30)
#   -c   Critical/fail if expiry is within this many days (default: 7)
#   -h   Show this help
#
# Exit codes: 0 = all OK, 1 = warning threshold hit, 2 = critical threshold hit

set -uo pipefail

WARN_DAYS=30
CRIT_DAYS=7
TARGETS=()
CERT_FILE=""

usage() {
  grep '^#' "$0" | sed -n '2,15p' | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while getopts ":t:f:w:c:h" opt; do
  case "$opt" in
    t) TARGETS+=("$OPTARG") ;;
    f) CERT_FILE="$OPTARG" ;;
    w) WARN_DAYS="$OPTARG" ;;
    c) CRIT_DAYS="$OPTARG" ;;
    h) usage 0 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage 1 ;;
    :) echo "Option -$OPTARG requires an argument" >&2; usage 1 ;;
  esac
done

if [[ ${#TARGETS[@]} -eq 0 && -z "$CERT_FILE" ]]; then
  echo "Specify at least one -t host:port or a -f cert file." >&2
  usage 1
fi

WORST_STATUS=0
NOW_EPOCH="$(date +%s)"

check_expiry() {
  local label="$1" end_date="$2"
  local end_epoch days_left status_label

  end_epoch="$(date -d "$end_date" +%s 2>/dev/null || date -j -f '%b %d %T %Y %Z' "$end_date" +%s 2>/dev/null)"
  if [[ -z "$end_epoch" ]]; then
    echo "  [UNKNOWN] $label — could not parse expiry date: $end_date"
    return
  fi

  days_left=$(( (end_epoch - NOW_EPOCH) / 86400 ))

  if (( days_left < CRIT_DAYS )); then
    status_label="CRITICAL"
    (( WORST_STATUS < 2 )) && WORST_STATUS=2
  elif (( days_left < WARN_DAYS )); then
    status_label="WARNING"
    (( WORST_STATUS < 1 )) && WORST_STATUS=1
  else
    status_label="OK"
  fi

  printf "  [%-8s] %-30s expires in %d day(s) (%s)\n" "$status_label" "$label" "$days_left" "$end_date"
}

if [[ -n "$CERT_FILE" ]]; then
  if [[ ! -f "$CERT_FILE" ]]; then
    echo "Cert file '$CERT_FILE' not found." >&2
    exit 1
  fi
  end_date="$(openssl x509 -enddate -noout -in "$CERT_FILE" 2>/dev/null | cut -d= -f2)"
  check_expiry "$CERT_FILE" "$end_date"
fi

for target in "${TARGETS[@]}"; do
  host="${target%%:*}"
  port="${target#*:}"
  [[ "$port" == "$target" ]] && port=443

  end_date="$(echo | timeout 10 openssl s_client -servername "$host" -connect "$host:$port" 2>/dev/null |
    openssl x509 -enddate -noout 2>/dev/null | cut -d= -f2)"

  if [[ -z "$end_date" ]]; then
    echo "  [UNKNOWN] $host:$port — could not retrieve certificate"
    (( WORST_STATUS < 1 )) && WORST_STATUS=1
    continue
  fi

  check_expiry "$host:$port" "$end_date"
done

exit "$WORST_STATUS"

