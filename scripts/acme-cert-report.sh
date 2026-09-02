#!/usr/bin/env bash
#
# acme-cert-report.sh — find the TLS certificates managed by an ACME client on
#   this host (Caddy, certbot, acme.sh, or a Traefik acme.json) and report each
#   one's domains, issuer, and days until expiry.
#
# Unlike cert-expiry-check.sh, which probes a live host:port, this inspects the
# on-disk certs a reverse proxy is actually managing — so you catch a cert
# that stopped renewing before a client does.
#
# Usage:
#   ./acme-cert-report.sh [-w DAYS] [-c DAYS] [-p PATH ...]
#
# Options:
#   -w DAYS  Warn if expiry is within this many days (default: 30).
#   -c DAYS  Critical/fail within this many days (default: 7).
#   -p PATH  Extra path to search (a directory of PEMs, or a Traefik
#            acme.json). Repeatable. Adds to the autodetected locations.
#   -h       Show this help.
#
# Autodetected: ~/.local/share/caddy/certificates, /var/lib/caddy/...,
#   /etc/letsencrypt/live, ~/.acme.sh, /etc/traefik/acme.json.
#
# Requires: openssl. jq is used for acme.json if present.
# Exit codes: 0 = all OK, 1 = warning threshold hit, 2 = critical threshold hit

set -uo pipefail

WARN=30 ; CRIT=7 ; EXTRA=()
usage() { grep -E '^#( |$)' "$0" | sed '1d; s/^# \{0,1\}//'; exit "${1:-0}"; }

while getopts ":w:c:p:h" opt; do
  case "$opt" in
    w) WARN="$OPTARG" ;;
    c) CRIT="$OPTARG" ;;
    p) EXTRA+=("$OPTARG") ;;
    h) usage 0 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage 2 ;;
    :) echo "Option -$OPTARG requires an argument" >&2; usage 2 ;;
  esac
done
command -v openssl >/dev/null 2>&1 || { echo "openssl is required." >&2; exit 2; }

WORST=0
NOW="$(date +%s)"

report() {  # $1 = label, $2 = "not-after" date string, $3 = issuer
  local label="$1" nafter="$2" issuer="$3" endep days state
  endep="$(date -d "$nafter" +%s 2>/dev/null || true)"
  if [ -z "$endep" ]; then
    printf '  [%-8s] %-45s (unparseable date: %s)\n' "UNKNOWN" "$label" "$nafter"
    [ "$WORST" -lt 1 ] && WORST=1
    return
  fi
  days=$(( (endep - NOW) / 86400 ))
  if   [ "$days" -lt "$CRIT" ]; then state=CRITICAL; [ "$WORST" -lt 2 ] && WORST=2
  elif [ "$days" -lt "$WARN" ]; then state=WARNING;  [ "$WORST" -lt 1 ] && WORST=1
  else state=OK
  fi
  printf '  [%-8s] %-45s %4d day(s)  [%s]\n' "$state" "$label" "$days" "${issuer:-?}"
}

scan_pem() {  # a single cert/fullchain PEM
  local f="$1" sub iss nafter
  openssl x509 -in "$f" -noout >/dev/null 2>&1 || return
  sub="$(openssl x509 -in "$f" -noout -subject 2>/dev/null | sed 's/^subject=//; s#.*CN *= *##; s/,.*//')"
  iss="$(openssl x509 -in "$f" -noout -issuer  2>/dev/null | sed 's#.*O *= *##; s/,.*//')"
  nafter="$(openssl x509 -in "$f" -noout -enddate 2>/dev/null | cut -d= -f2)"
  report "${sub:-$f}" "$nafter" "$iss"
}

scan_dir() {  # directory of PEMs (Caddy / certbot layout)
  local d="$1"
  [ -d "$d" ] || return
  echo "== $d"
  find "$d" -type f \( -name '*.crt' -o -name 'fullchain.pem' -o -name 'cert.pem' -o -name '*.pem' \) 2>/dev/null \
    | grep -viE 'key|chain-only|privkey' | sort -u | while IFS= read -r f; do scan_pem "$f"; done
}

scan_acme_json() {  # Traefik acme.json
  local j="$1"
  [ -f "$j" ] || return
  command -v jq >/dev/null 2>&1 || { echo "== $j (jq needed to read Traefik acme.json)"; return; }
  echo "== $j"
  jq -r '.. | objects | select(.certificate? and .domain?) |
         (.domain.main // (.domain.sans[0] // "?")) + "\t" + .certificate' "$j" 2>/dev/null \
    | while IFS=$'\t' read -r dom b64; do
        [ -n "$b64" ] || continue
        tmp="$(mktemp)"; printf '%s' "$b64" | base64 -d > "$tmp" 2>/dev/null
        nafter="$(openssl x509 -in "$tmp" -noout -enddate 2>/dev/null | cut -d= -f2)"
        iss="$(openssl x509 -in "$tmp" -noout -issuer 2>/dev/null | sed 's#.*O *= *##; s/,.*//')"
        report "$dom" "$nafter" "$iss"
        rm -f "$tmp"
      done
}

for d in "$HOME/.local/share/caddy/certificates" \
         "/var/lib/caddy/.local/share/caddy/certificates" \
         "/etc/letsencrypt/live" \
         "$HOME/.acme.sh"; do
  scan_dir "$d"
done
scan_acme_json "/etc/traefik/acme.json"

for p in "${EXTRA[@]:-}"; do
  [ -z "$p" ] && continue
  if   [ "${p%.json}" != "$p" ]; then scan_acme_json "$p"
  elif [ -d "$p" ];              then scan_dir "$p"
  else                               scan_pem "$p"
  fi
done

echo
case "$WORST" in
  0) echo "All managed certificates OK." ;;
  1) echo "One or more certificates near expiry (warning)." >&2 ;;
  2) echo "One or more certificates CRITICALLY close to expiry." >&2 ;;
esac
exit "$WORST"
