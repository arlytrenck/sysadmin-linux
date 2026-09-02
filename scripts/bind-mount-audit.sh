#!/usr/bin/env bash
#
# bind-mount-audit.sh — enumerate every host bind mount across running
#   containers and flag the risky ones: writable mounts of sensitive host
#   paths, the Docker socket, a user's home, and mounts whose host path
#   doesn't exist.
#
# Usage:
#   ./bind-mount-audit.sh [-a]
#
# Options:
#   -a   List every bind mount, not just the flagged ones.
#   -h   Show this help.
#
# Exit codes: 0 = nothing flagged, 1 = one or more risky mounts,
#             2 = docker unavailable

set -uo pipefail

SHOW_ALL=0
usage() { grep -E '^#( |$)' "$0" | sed '1d; s/^# \{0,1\}//'; exit "${1:-0}"; }

while getopts ":ah" opt; do
  case "$opt" in
    a) SHOW_ALL=1 ;;
    h) usage 0 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage 2 ;;
  esac
done

command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 \
  || { echo "docker not available / daemon not reachable." >&2; exit 2; }

# Host paths that are dangerous to bind-mount, especially writable.
is_sensitive() {
  case "$1" in
    /|/etc|/etc/*|/root|/root/*|/boot|/boot/*|/sys|/sys/*|/proc|/proc/*|\
    /var/run/docker.sock|/run/docker.sock|/var/lib/docker|/var/lib/docker/*|\
    /usr|/usr/*|/bin|/bin/*|/sbin|/sbin/*|/lib|/lib/*) return 0 ;;
    /home/*|/Users/*) return 0 ;;
    *) return 1 ;;
  esac
}

flagged=0
printf '%-22s %-8s %-40s %s\n' "CONTAINER" "MODE" "HOST PATH" "NOTE"
printf '%-22s %-8s %-40s %s\n' "---------" "----" "---------" "----"

while IFS= read -r id; do
  [ -n "$id" ] || continue
  name="$(docker inspect --format '{{.Name}}' "$id" | sed 's#^/##')"
  while IFS=$'\t' read -r src dst rw; do
    [ -n "$src" ] || continue
    mode="ro"; [ "$rw" = "true" ] && mode="rw"

    note=""
    [ ! -e "$src" ] && note="host path missing"
    if is_sensitive "$src"; then
      if [ "$mode" = "rw" ]; then note="${note:+$note; }WRITABLE sensitive path"
      else note="${note:+$note; }sensitive path (ro)"; fi
    fi
    case "$src" in */docker.sock) note="${note:+$note; }docker socket = root on host" ;; esac

    if [ -n "$note" ]; then
      printf '%-22s %-8s %-40s %s\n' "$name" "$mode" "$src -> $dst" "$note"
      flagged=1
    elif [ "$SHOW_ALL" -eq 1 ]; then
      printf '%-22s %-8s %-40s %s\n' "$name" "$mode" "$src -> $dst" "-"
    fi
  done < <(docker inspect --format \
    '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}}{{"\t"}}{{.Destination}}{{"\t"}}{{.RW}}{{"\n"}}{{end}}{{end}}' "$id")
done < <(docker ps -q)

echo
[ "$flagged" -eq 0 ] && { echo "No risky bind mounts found."; exit 0; }
echo "Review the flagged mounts above." >&2
exit 1
