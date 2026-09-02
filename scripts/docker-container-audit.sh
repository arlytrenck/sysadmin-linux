#!/usr/bin/env bash
#
# docker-container-audit.sh - flag common Docker container misconfigurations
#   on a host running the Docker Engine.
#
# Checks each running container for:
#   - running as root (or with no USER set, defaulting to root)
#   - --privileged mode
#   - no memory limit set (unbounded, can starve the host)
#   - published ports bound to 0.0.0.0 (reachable beyond localhost)
#   - restart-loop behaviour (high restart count)
#
# Usage: ./docker-container-audit.sh [-h]
#
# Exit codes: 0 = nothing flagged, 1 = one or more issues flagged,
#             2 = docker not available / not usable

set -uo pipefail

usage() {
    echo "Usage: $0 [-h]"
    echo "  Audits running Docker containers for common misconfigurations."
    exit 0
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage

if ! command -v docker >/dev/null 2>&1; then
    echo "docker not found on this host."
    exit 2
fi

if ! docker info >/dev/null 2>&1; then
    echo "Could not talk to the Docker daemon (not running, or insufficient permission)."
    exit 2
fi

flagged=0
containers=$(docker ps -q)

if [[ -z "$containers" ]]; then
    echo "No running containers."
    exit 0
fi

for cid in $containers; do
    name=$(docker inspect -f '{{.Name}}' "$cid" | sed 's#^/##')
    echo "=== $name ($cid) ==="

    user=$(docker inspect -f '{{.Config.User}}' "$cid")
    if [[ -z "$user" || "$user" == "0" || "$user" == "root" ]]; then
        echo "  [FLAG] running as root (no non-root USER set)"
        flagged=1
    fi

    privileged=$(docker inspect -f '{{.HostConfig.Privileged}}' "$cid")
    if [[ "$privileged" == "true" ]]; then
        echo "  [FLAG] running with --privileged"
        flagged=1
    fi

    mem_limit=$(docker inspect -f '{{.HostConfig.Memory}}' "$cid")
    if [[ "$mem_limit" == "0" ]]; then
        echo "  [FLAG] no memory limit set (unbounded)"
        flagged=1
    fi

    ports=$(docker inspect -f '{{range $p, $conf := .NetworkSettings.Ports}}{{range $conf}}{{.HostIp}}:{{.HostPort}} {{end}}{{end}}' "$cid")
    if echo "$ports" | grep -q '0\.0\.0\.0'; then
        echo "  [FLAG] port(s) published on 0.0.0.0 (reachable beyond localhost): $ports"
        flagged=1
    fi

    restart_count=$(docker inspect -f '{{.RestartCount}}' "$cid")
    if [[ "$restart_count" -ge 5 ]]; then
        echo "  [FLAG] restart count is $restart_count (possible restart loop)"
        flagged=1
    fi

    status=$(docker inspect -f '{{.State.Status}}' "$cid")
    echo "  status=$status user='${user:-<unset>}' privileged=$privileged mem_limit=$mem_limit restarts=$restart_count"
done

echo ""
if [[ "$flagged" -eq 1 ]]; then
    echo "One or more containers were flagged above."
else
    echo "Nothing flagged."
fi
exit "$flagged"
