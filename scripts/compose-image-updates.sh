#!/usr/bin/env bash
#
# compose-image-updates.sh — for every image referenced by a set of Compose
#   files (or every image on running compose containers), check the registry
#   for a newer digest than the one currently in use.
#
# This covers the gap left by auto-updaters that skip pinned tags: an image
# pinned to `:1.2.3` or `@sha256:...` never advances on its own, but the
# upstream tag may have moved or a `:latest` may have a new digest.
#
# Usage:
#   ./compose-image-updates.sh [-d DIR] [-r]
#
# Options:
#   -d DIR   Directory to scan for compose files (default: current directory).
#   -r       Check running compose containers instead of parsing files.
#   -h       Show this help.
#
# Requires one of: skopeo, crane, or docker (with `docker buildx imagetools`).
# Exit codes: 0 = everything current, 1 = update(s) available,
#             2 = usage / no registry tool available

set -uo pipefail

DIR="." ; FROM_RUNNING=0
usage() { grep -E '^#( |$)' "$0" | sed '1d; s/^# \{0,1\}//'; exit "${1:-0}"; }

while getopts ":d:rh" opt; do
  case "$opt" in
    d) DIR="$OPTARG" ;;
    r) FROM_RUNNING=1 ;;
    h) usage 0 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage 2 ;;
    :) echo "Option -$OPTARG requires an argument" >&2; usage 2 ;;
  esac
done

TOOL=""
if   command -v skopeo >/dev/null 2>&1; then TOOL=skopeo
elif command -v crane  >/dev/null 2>&1; then TOOL=crane
elif command -v docker >/dev/null 2>&1 && docker buildx version >/dev/null 2>&1; then TOOL=docker
else echo "Need skopeo, crane, or docker buildx to query registries." >&2; exit 2; fi

# remote digest for a ref (the manifest-list / index digest)
remote_digest() {
  local ref="$1"
  case "$TOOL" in
    skopeo) skopeo inspect --raw "docker://$ref" 2>/dev/null | sha256sum | awk '{print "sha256:"$1}' ;;
    crane)  crane digest "$ref" 2>/dev/null ;;
    docker) docker buildx imagetools inspect "$ref" 2>/dev/null | awk '/^Digest:/{print $2; exit}' ;;
  esac
}

# collect image refs
IMAGES=()
if [ "$FROM_RUNNING" -eq 1 ]; then
  command -v docker >/dev/null 2>&1 || { echo "-r needs docker." >&2; exit 2; }
  mapfile -t IMAGES < <(docker ps --filter "label=com.docker.compose.project" \
    --format '{{.Image}}' | sort -u)
else
  mapfile -t FILES < <(find "$DIR" -type f \( -name 'compose.yml' -o -name 'compose.yaml' \
    -o -name 'docker-compose.yml' -o -name 'docker-compose.yaml' \) | sort)
  [ "${#FILES[@]}" -gt 0 ] || { echo "No compose files under $DIR" >&2; exit 2; }
  mapfile -t IMAGES < <(
    grep -hE '^\s*image:\s*' "${FILES[@]}" \
      | sed -E 's/^\s*image:\s*//; s/["'\'']//g' \
      | grep -v '\${' | sort -u
  )
fi
[ "${#IMAGES[@]}" -gt 0 ] || { echo "No concrete image refs found (all templated?)."; exit 0; }

updates=0
printf '%-45s %s\n' "IMAGE" "STATUS"
printf '%-45s %s\n' "-----" "------"

for ref in "${IMAGES[@]}"; do
  # A digest-pinned ref can't "update" without the compose file changing.
  case "$ref" in *@sha256:*) printf '%-45s %s\n' "$ref" "digest-pinned (change the file to move it)"; continue ;; esac

  local_digest="$(docker image inspect "$ref" --format '{{index .RepoDigests 0}}' 2>/dev/null | sed 's/.*@//')"
  rd="$(remote_digest "$ref")"

  if [ -z "$rd" ]; then
    printf '%-45s %s\n' "$ref" "could not query registry"
  elif [ -z "$local_digest" ]; then
    printf '%-45s %s\n' "$ref" "not pulled locally; remote ${rd:0:19}..."
  elif [ "$local_digest" = "$rd" ]; then
    printf '%-45s %s\n' "$ref" "up to date"
  else
    printf '%-45s %s\n' "$ref" "UPDATE: local ${local_digest:0:19}... -> remote ${rd:0:19}..."
    updates=1
  fi
done

echo
[ "$updates" -eq 0 ] && { echo "All images current."; exit 0; }
echo "Updates are available (pull + recreate to apply)." >&2
exit 1
