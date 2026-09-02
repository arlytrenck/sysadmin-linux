#!/usr/bin/env bash
#
# healthcheck-audit.sh — report on container health across a Docker host:
#   which running containers define no HEALTHCHECK, which are currently
#   unhealthy, and which are restart-looping.
#
# On a single-node stack, "no healthcheck" means an orchestrator (or an
# autoheal sidecar) can't tell a wedged container from a working one.
#
# Requires bash 4.4+ (empty-array expansion under set -u).
#
# Usage:
#   ./healthcheck-audit.sh [-r N] [-a]
#
# Options:
#   -r N   Restart-count threshold to flag as looping (default: 5).
#   -a     Also list containers that ARE healthy (default: only problems).
#   -h     Show this help.
#
# Exit codes: 0 = nothing flagged, 1 = one or more issues, 2 = docker unavailable

set -uo pipefail

THRESH=5 ; SHOW_OK=0
usage() { grep -E '^#( |$)' "$0" | sed '1d; s/^# \{0,1\}//'; exit "${1:-0}"; }

while getopts ":r:ah" opt; do
  case "$opt" in
    r) THRESH="$OPTARG" ;;
    a) SHOW_OK=1 ;;
    h) usage 0 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage 2 ;;
    :) echo "Option -$OPTARG requires an argument" >&2; usage 2 ;;
  esac
done
case "$THRESH" in ''|*[!0-9]*) echo "-r must be a number." >&2; exit 2 ;; esac

command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 \
  || { echo "docker not available / daemon not reachable." >&2; exit 2; }

flagged=0
no_hc=() ; unhealthy=() ; looping=() ; healthy=()

while IFS= read -r id; do
  [ -n "$id" ] || continue
  name="$(docker inspect --format '{{.Name}}' "$id" | sed 's#^/##')"
  has_hc="$(docker inspect --format '{{if .Config.Healthcheck}}yes{{else}}no{{end}}' "$id")"
  hstatus="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$id")"
  restarts="$(docker inspect --format '{{.RestartCount}}' "$id")"

  if [ "$has_hc" = "no" ]; then no_hc+=("$name"); flagged=1; fi
  if [ "$hstatus" = "unhealthy" ]; then unhealthy+=("$name"); flagged=1; fi
  if [ "${restarts:-0}" -ge "$THRESH" ]; then looping+=("$name (restarts=$restarts)"); flagged=1; fi
  if [ "$has_hc" = "yes" ] && [ "$hstatus" = "healthy" ] && [ "${restarts:-0}" -lt "$THRESH" ]; then
    healthy+=("$name")
  fi
done < <(docker ps -q)

section() {
  local title="$1"; shift
  printf '\n== %s (%d) ==\n' "$title" "$#"
  if [ "$#" -eq 0 ]; then echo "  (none)"; else printf '  %s\n' "$@"; fi
}

section "no HEALTHCHECK defined" "${no_hc[@]}"
section "currently unhealthy" "${unhealthy[@]}"
section "restart-looping (>= $THRESH)" "${looping[@]}"
[ "$SHOW_OK" -eq 1 ] && section "healthy" "${healthy[@]}"

echo
[ "$flagged" -eq 0 ] && { echo "All running containers look healthy."; exit 0; }
echo "Issues found." >&2
exit 1
