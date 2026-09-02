#!/usr/bin/env bash
#
# compose-validate.sh — run `docker compose config` against every Compose file
#   found under a directory, so a malformed stack is caught before deploy.
#
# Unset ${VAR} references only warn — a bare ${VAR} or ${VAR:-default} is fine
# without a value. A ${VAR:?msg} reference (colon-question) does report as
# invalid when the value is absent: that is compose telling you the stack is
# not runnable without it.
#
# Usage:
#   ./compose-validate.sh [-d DIR]
#
# Options:
#   -d DIR   Directory to scan (default: current directory).
#   -h       Show this help.
#
# Exit codes: 0 = all valid, 1 = one or more invalid,
#             2 = usage error / `docker compose` unavailable

set -uo pipefail

DIR="."
usage() { grep -E "^#( |$)" "$0" | sed "1d;s/^#\\s\\?//"; exit "${1:-0}"; }

while getopts ":d:h" opt; do
  case "$opt" in
    d) DIR="$OPTARG" ;;
    h) usage 0 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage 2 ;;
    :) echo "Option -$OPTARG requires an argument" >&2; usage 2 ;;
  esac
done

[ -d "$DIR" ] || { echo "Not a directory: $DIR" >&2; exit 2; }

if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
  echo "'docker compose' (v2) not available on this host." >&2
  exit 2
fi

mapfile -t COMPOSE < <(find "$DIR" -type f \( -name 'compose.yml' -o -name 'compose.yaml' \
  -o -name 'docker-compose.yml' -o -name 'docker-compose.yaml' \) | sort)

if [ "${#COMPOSE[@]}" -eq 0 ]; then
  echo "No compose files found under $DIR" >&2
  exit 2
fi

rc=0
made_env=()
cleanup() { local e; for e in "${made_env[@]:-}"; do [ -n "$e" ] && rm -f "$e"; done; }
trap cleanup EXIT

env_file_targets() {  # $1 = compose file
  awk '
    /^[[:space:]]*env_file:[[:space:]]*\[/ {
      s = $0; sub(/.*\[/, "", s); sub(/\].*/, "", s)
      n = split(s, a, ",")
      for (i = 1; i <= n; i++) { gsub(/[[:space:]"'"'"']/, "", a[i]); if (a[i] != "") print a[i] }
      next
    }
    /^[[:space:]]*env_file:[[:space:]]*[^[:space:]#]/ { v = $2; gsub(/["'"'"']/, "", v); print v; next }
    /^[[:space:]]*env_file:[[:space:]]*$/ { blk = 1; next }
    blk && /^[[:space:]]*-[[:space:]]*/ { v = $2; gsub(/["'"'"']/, "", v); print v; next }
    blk { blk = 0 }
  ' "$1"
}

for f in "${COMPOSE[@]}"; do
  d="$(dirname "$f")"
  # `config` needs referenced env files (incl. the implicit project .env) to
  # exist. Create empty throwaways where missing; remove them on exit.
  while IFS= read -r ef; do
    [ -n "$ef" ] || continue
    ep="$d/$ef"
    [ -e "$ep" ] || { : > "$ep" && made_env+=("$ep"); }
  done < <(env_file_targets "$f"; echo ".env")

  printf -- '--- %s\n' "$f"
  if docker compose -f "$f" config -q \
       2> >(grep -v -e 'variable is not set' -e 'Defaulting to a blank string' >&2); then
    echo "    ok"
  else
    echo "    INVALID"
    rc=1
  fi
done

if [ "$rc" -eq 0 ]; then
  echo "All ${#COMPOSE[@]} compose file(s) valid."
else
  echo "One or more compose files are invalid." >&2
fi
exit "$rc"
