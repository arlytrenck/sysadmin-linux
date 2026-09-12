#!/usr/bin/env bash
#
# docker-service-maintenance.sh — automate health and status checks for a
# Docker Compose stack.
#
# Usage:
#   ./docker-service-maintenance.sh [-d /path/to/stack] [-h]
#
# Options:
#   -d   Directory containing the docker-compose.yml (default: .)
#   -h   Show this help

set -euo pipefail

STACK_DIR="."

usage() { sed -n '2,/^[^#]/p' "$0" | sed '1{/^#$/d;}; $d; s/^# \{0,1\}//'; exit "${1:-0}"; }

while getopts ":d:h" opt; do
  case "$opt" in
    d) STACK_DIR="$OPTARG" ;;
    h) usage 0 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage 1 ;;
    :) echo "Option -$OPTARG requires an argument" >&2; usage 1 ;;
  esac
done

if [[ ! -d "$STACK_DIR" ]]; then
  echo "Error: Directory $STACK_DIR does not exist." >&2
  exit 1
fi

cd "$STACK_DIR" || exit 1

echo "=== Checking stack in $(pwd) ==="

echo "--- 1. Container Status ---"
docker compose ps

echo
echo "--- 2. Health Checks ---"
# Check if any container is in an unhealthy state
if docker compose ps --format json | jq -e 'select(.Health == "unhealthy")' >/dev/null 2>&1; then
    echo "WARNING: One or more containers are unhealthy."
else
    echo "All containers healthy."
fi

echo
echo "--- 3. Restart Loops ---"
# Check for containers restarting frequently
if docker compose ps --format json | jq -e 'select(.State == "running" and (.Status | contains("Restarting")))' >/dev/null 2>&1; then
    echo "WARNING: Some containers are restarting."
else
    echo "No containers restarting."
fi

echo
echo "Maintenance check complete."
