#!/usr/bin/env bash
#
# grafana-dashboard-export.sh — export Grafana dashboards, datasources, folders
#   and unified alerting to JSON, so a monitoring stack has git history and is
#   restorable. READ-ONLY against the Grafana HTTP API.
#
# Usage:
#   GRAFANA_URL=http://localhost:3000 GRAFANA_TOKEN=glsa_xxx \
#     ./grafana-dashboard-export.sh [-o OUTDIR]
#
#   # basic auth instead of a token:
#   GRAFANA_URL=... GRAFANA_USER=admin GRAFANA_PASS=... ./grafana-dashboard-export.sh
#
# Options:
#   -o DIR   Output directory (default: ./grafana-export).
#   -h       Show this help.
#
# Secrets in datasources (`secureJsonData`) and contact points (passwords,
# tokens) are redacted before writing. Dashboards are saved as the portable
# model with the internal numeric id nulled and the uid kept.
#
# Requires: curl, jq.
# Exit codes: 0 = OK, 2 = usage / missing dependency / auth not provided

set -uo pipefail

OUT="./grafana-export"
usage() { grep -E "^#( |$)" "$0" | sed "1d;s/^#\\s\\?//"; exit "${1:-0}"; }

while getopts ":o:h" opt; do
  case "$opt" in
    o) OUT="$OPTARG" ;;
    h) usage 0 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage 2 ;;
    :) echo "Option -$OPTARG requires an argument" >&2; usage 2 ;;
  esac
done

command -v curl >/dev/null 2>&1 || { echo "curl is required." >&2; exit 2; }
command -v jq   >/dev/null 2>&1 || { echo "jq is required."   >&2; exit 2; }

URL="${GRAFANA_URL:-}"
[ -n "$URL" ] || { echo "Set GRAFANA_URL (e.g. http://localhost:3000)." >&2; exit 2; }
URL="${URL%/}"

if [ -n "${GRAFANA_TOKEN:-}" ]; then
  AUTH=(-H "Authorization: Bearer ${GRAFANA_TOKEN}")
elif [ -n "${GRAFANA_USER:-}" ] && [ -n "${GRAFANA_PASS:-}" ]; then
  AUTH=(-u "${GRAFANA_USER}:${GRAFANA_PASS}")
else
  echo "Provide GRAFANA_TOKEN, or GRAFANA_USER + GRAFANA_PASS." >&2
  exit 2
fi

api() { curl -fsS "${AUTH[@]}" "$URL/api/$1" 2>/dev/null; }

scrub() {
  jq '
    def mask:
      if type == "object" then
        with_entries(
          if (.key | test("(?i)(password|secret|token|apikey|api_key|basicauthpassword)")) then .value = "<REDACTED>"
          elif .key == "secureJsonData" then .value = "<REDACTED>"
          else .value |= mask end)
      elif type == "array" then map(mask)
      else . end;
    mask'
}

rm -rf "$OUT"
mkdir -p "$OUT/dashboards" "$OUT/datasources" "$OUT/alerting" "$OUT/meta"

echo "== meta =="
api "health"        | jq .              > "$OUT/meta/health.json"  && echo "  + meta/health.json"
api "org"           | jq .              > "$OUT/meta/org.json"     && echo "  + meta/org.json"
api "folders"       | jq 'sort_by(.title)' > "$OUT/folders.json"   && echo "  + folders.json"

echo "== datasources =="
api "datasources"   | scrub | jq 'sort_by(.name)' > "$OUT/datasources/_all.json" \
  && echo "  + datasources/_all.json"

echo "== dashboards =="
count=0
while IFS= read -r uid; do
  [ -n "$uid" ] || continue
  j="$(api "dashboards/uid/$uid")" || { echo "  ~ $uid (fetch failed)"; continue; }
  folder="$(printf '%s' "$j" | jq -r '.meta.folderTitle // "General"' | tr -c 'A-Za-z0-9._-' '_')"
  slug="$(printf '%s' "$j" | jq -r '.dashboard.title' | tr -c 'A-Za-z0-9._-' '_' | cut -c1-80)"
  mkdir -p "$OUT/dashboards/$folder"
  printf '%s' "$j" | jq '.dashboard | .id = null' > "$OUT/dashboards/$folder/$slug.json"
  echo "  + dashboards/$folder/$slug.json"
  count=$((count + 1))
done < <(api "search?type=dash-db&limit=5000" | jq -r '.[].uid')

echo "== alerting (unified) =="
for ep in \
  "v1/provisioning/alert-rules:alert-rules.json" \
  "v1/provisioning/contact-points:contact-points.json" \
  "v1/provisioning/policies:notification-policies.json" \
  "v1/provisioning/mute-timings:mute-timings.json" \
  "v1/provisioning/templates:templates.json"; do
  p="${ep%%:*}"; fn="${ep##*:}"
  if api "$p" | scrub | jq . > "$OUT/alerting/$fn" 2>/dev/null; then
    echo "  + alerting/$fn"
  else
    echo "  ~ alerting/$fn (unavailable on this Grafana version)"
    rm -f "$OUT/alerting/$fn"
  fi
done

{
  echo "generated: $(date -u '+%Y-%m-%d %H:%M UTC')  from $URL"
  echo "dashboards: $count   (portable model; .id nulled, .uid kept)"
  echo "secrets in datasources / contact points are redacted"
  echo "restore a dashboard: POST /api/dashboards/db  {\"dashboard\": <file>, \"overwrite\": true}"
} > "$OUT/README.txt"

echo "OK  $OUT/  ($count dashboards)"
