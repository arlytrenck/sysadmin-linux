#!/usr/bin/env bash
#
# tailscale-export.sh — snapshot this node's Tailscale state (and, optionally,
#   the tailnet-wide config) to redacted JSON, so it's versioned and diffable.
#   READ-ONLY: queries state and writes files, changes nothing.
#
# Usage:
#   ./tailscale-export.sh [-o OUTDIR]              # on-node state (no token)
#   TS_API_KEY=tskey-api-xxxx ./tailscale-export.sh --api   # + tailnet ACL/DNS/devices
#
# Options:
#   -o DIR    Output directory (default: ./tailscale-export).
#   --api     Also pull tailnet-wide config from the Tailscale API. Needs
#             TS_API_KEY (a read-only API access token from the admin console).
#   -h        Show this help.
#
# Never exported: node/machine private keys, auth keys, API tokens — those are
#   redacted or simply not read. `/var/lib/tailscale/tailscaled.state` is never
#   touched.
#
# Requires: tailscale (CLI); curl for --api. python3 or jq for pretty-printing
#   (falls back to raw).
# Exit codes: 0 = OK, 2 = usage / tailscale CLI not found

set -uo pipefail

OUT="./tailscale-export"
DO_API=0
usage() { grep -E "^#( |$)" "$0" | sed "1d;s/^#\\s\\?//"; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    -o) OUT="${2:?-o needs a directory}"; shift 2 ;;
    --api) DO_API=1; shift ;;
    -h|--help) usage 0 ;;
    *) echo "Unknown argument: $1" >&2; usage 2 ;;
  esac
done

command -v tailscale >/dev/null 2>&1 || { echo "tailscale CLI not found." >&2; exit 2; }

pretty() {
  if command -v jq >/dev/null 2>&1; then jq -S . 2>/dev/null || cat
  elif command -v python3 >/dev/null 2>&1; then python3 -m json.tool --sort-keys 2>/dev/null || cat
  else cat
  fi
}

# Redact anything key/secret/token-shaped. Deliberately over-broad — a stored
# snapshot doesn't need public node keys either.
scrub() {
  sed -E \
    -e 's/(tskey-[a-zA-Z0-9-]{6})[a-zA-Z0-9-]+/\1<REDACTED>/g' \
    -e 's/(node|nodekey|mkey|machine)[:-][a-f0-9]{16,}/\1:<REDACTED>/gI' \
    -e 's/("[A-Za-z0-9_]*([Kk]ey|[Ss]ecret|[Tt]oken|[Aa]uth|[Pp]assword)[A-Za-z0-9_]*"[[:space:]]*:[[:space:]]*)"[^"]*"/\1"<REDACTED>"/g'
}

mkdir -p "$OUT/local"
echo "== local (on-node) =="
tailscale version                              >  "$OUT/local/version.txt" 2>&1 && echo "  + local/version.txt"
tailscale status --json 2>/dev/null | scrub | pretty > "$OUT/local/status.json" && echo "  + local/status.json"
tailscale status       2>/dev/null            >  "$OUT/local/status.txt"   && echo "  + local/status.txt"
tailscale debug prefs   2>/dev/null | scrub | pretty > "$OUT/local/prefs.json" && echo "  + local/prefs.json"
tailscale ip -4         2>/dev/null            >  "$OUT/local/ip4.txt"      || true
tailscale netcheck --format json 2>/dev/null | scrub | pretty > "$OUT/local/netcheck.json" && echo "  + local/netcheck.json"

if [ "$DO_API" -eq 1 ]; then
  command -v curl >/dev/null 2>&1 || { echo "curl required for --api." >&2; exit 2; }
  : "${TS_API_KEY:?set TS_API_KEY (read-only API token from the admin console)}"
  mkdir -p "$OUT/tailnet"
  base="https://api.tailscale.com/api/v2/tailnet/-"
  get() { curl -fsSL -u "${TS_API_KEY}:" "$base/$1" 2>/dev/null; }

  echo "== tailnet (API) =="
  curl -fsSL -u "${TS_API_KEY}:" -H 'Accept: application/hujson' "$base/acl" 2>/dev/null \
    | scrub > "$OUT/tailnet/acl.hujson"          && echo "  + tailnet/acl.hujson"
  get acl                | scrub | pretty > "$OUT/tailnet/acl.json"          && echo "  + tailnet/acl.json"
  get devices            | scrub | pretty > "$OUT/tailnet/devices.json"      && echo "  + tailnet/devices.json"
  get dns/nameservers    | scrub | pretty > "$OUT/tailnet/dns-nameservers.json" && echo "  + tailnet/dns-nameservers.json"
  get dns/preferences    | scrub | pretty > "$OUT/tailnet/dns-preferences.json" && echo "  + tailnet/dns-preferences.json"
  get keys               | scrub | pretty > "$OUT/tailnet/keys.json"         && echo "  + tailnet/keys.json (metadata only)"
  find "$OUT/tailnet" -type f -size -3c -delete
fi

{
  echo "generated: $(date -u '+%Y-%m-%d %H:%M UTC')  on $(hostname)"
  echo "local/   = on-node state; tailnet/ = account-wide config (only with --api)"
  echo "redacted: auth keys, API tokens, node/machine keys"
} > "$OUT/README.txt"

echo "OK  $OUT/"
