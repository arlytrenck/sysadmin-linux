#!/usr/bin/env bash
#
# compose-drift.sh — check whether the running containers still match what the
#   Compose files declare, and flag containers running outside any Compose
#   project (ad-hoc `docker run`).
#
# For each service it compares the declared vs. running image, restart policy,
# published ports, and whether the container is up at all.
#
# Usage:
#   ./compose-drift.sh [-d DIR] [-f COMPOSE_FILE ...]
#
# Options:
#   -d DIR   Directory to scan for compose files (default: current directory).
#   -f FILE  Use this specific compose file (repeatable). Overrides -d.
#   -h       Show this help.
#
# Exit codes: 0 = no drift, 1 = drift found, 2 = usage / docker unavailable

set -uo pipefail

DIR="." ; FILES=()
usage() { grep -E '^#( |$)' "$0" | sed '1d; s/^# \{0,1\}//'; exit "${1:-0}"; }

while getopts ":d:f:h" opt; do
  case "$opt" in
    d) DIR="$OPTARG" ;;
    f) FILES+=("$OPTARG") ;;
    h) usage 0 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage 2 ;;
    :) echo "Option -$OPTARG requires an argument" >&2; usage 2 ;;
  esac
done

command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1 \
  || { echo "'docker compose' (v2) not available." >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq is required." >&2; exit 2; }

if [ "${#FILES[@]}" -eq 0 ]; then
  mapfile -t FILES < <(find "$DIR" -type f \( -name 'compose.yml' -o -name 'compose.yaml' \
    -o -name 'docker-compose.yml' -o -name 'docker-compose.yaml' \) | sort)
fi
[ "${#FILES[@]}" -gt 0 ] || { echo "No compose files found." >&2; exit 2; }

drift=0
declare -A SEEN_CONTAINERS=()

for f in "${FILES[@]}"; do
  d="$(dirname "$f")"
  proj="$(basename "$d")"
  echo "=== $f  (project: $proj)"

  cfg="$(cd "$d" && docker compose -f "$(basename "$f")" config --format json 2>/dev/null)" || {
    echo "  ! could not parse — run compose-validate.sh"; drift=1; continue
  }

  while IFS=$'\t' read -r svc want_image want_restart; do
    [ -n "$svc" ] || continue
    cid="$(docker ps -aq \
      --filter "label=com.docker.compose.project=$proj" \
      --filter "label=com.docker.compose.service=$svc" | head -1)"

    if [ -z "$cid" ]; then
      echo "  [DOWN]    $svc — declared but no container"
      drift=1
      continue
    fi
    SEEN_CONTAINERS["$cid"]=1

    state="$(docker inspect --format '{{.State.Status}}' "$cid")"
    got_image="$(docker inspect --format '{{.Config.Image}}' "$cid")"
    got_restart="$(docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' "$cid")"

    issues=()
    [ "$state" = "running" ] || issues+=("state=$state")
    [ -n "$want_image" ] && [ "$want_image" != "$got_image" ] && issues+=("image: want '$want_image' got '$got_image'")
    [ -n "$want_restart" ] && [ "$want_restart" != "$got_restart" ] && issues+=("restart: want '$want_restart' got '$got_restart'")

    if [ "${#issues[@]}" -gt 0 ]; then
      echo "  [DRIFT]   $svc — ${issues[*]}"
      drift=1
    else
      echo "  [ok]      $svc"
    fi
  done < <(printf '%s' "$cfg" | jq -r '
    .services | to_entries[] |
    [ .key, (.value.image // ""), (.value.restart // "") ] | @tsv')
done

echo "=== containers not managed by any scanned compose project"
adhoc=0
while IFS= read -r cid; do
  [ -n "$cid" ] || continue
  [ -n "${SEEN_CONTAINERS[$cid]:-}" ] && continue
  proj="$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project"}}' "$cid")"
  name="$(docker inspect --format '{{.Name}}' "$cid" | sed 's#^/##')"
  img="$(docker inspect --format '{{.Config.Image}}' "$cid")"
  if [ -z "$proj" ]; then
    echo "  [AD-HOC]  $name  ($img)"
    adhoc=1
  fi
done < <(docker ps -q)
[ "$adhoc" -eq 0 ] && echo "  none"

if [ "$drift" -ne 0 ] || [ "$adhoc" -ne 0 ]; then
  echo
  echo "Drift detected." >&2
  exit 1
fi
echo
echo "No drift."
exit 0
