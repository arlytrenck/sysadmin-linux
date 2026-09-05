#!/usr/bin/env bash
#
# stack-db-dump.sh — find the database containers among a set of Docker Compose
#   stacks and dump each one to a compressed file. Handles PostgreSQL, MySQL/
#   MariaDB, SQLite (via a file copy), and Redis (BGSAVE + RDB copy).
#
# Usage:
#   ./stack-db-dump.sh -o DIR [-p PROJECT] [-n]
#
# Options:
#   -o DIR    Output directory for the dumps (required).
#   -p NAME   Only dump containers belonging to this compose project.
#   -n        Dry run: list what would be dumped, don't dump.
#   -h        Show this help.
#
# Detection is by image name (postgres/mariadb/mysql/redis/...) and by the
# presence of a `*.sqlite`/`*.db` file under a bind mount. Credentials are read
# from the container's own environment (POSTGRES_USER, MYSQL_ROOT_PASSWORD,
# etc.) — nothing is passed on the command line or logged.
#
# Exit codes: 0 = OK (or nothing found), 1 = one or more dumps failed,
#             2 = usage / docker unavailable

set -uo pipefail

OUT="" ; PROJECT="" ; DRY=0
usage() { grep -E '^#( |$)' "$0" | sed '1d; s/^# \{0,1\}//'; exit "${1:-0}"; }

while getopts ":o:p:nh" opt; do
  case "$opt" in
    o) OUT="$OPTARG" ;;
    p) PROJECT="$OPTARG" ;;
    n) DRY=1 ;;
    h) usage 0 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage 2 ;;
    :) echo "Option -$OPTARG requires an argument" >&2; usage 2 ;;
  esac
done

[ -n "$OUT" ] || { echo "-o DIR is required." >&2; usage 2; }
command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 \
  || { echo "docker not available / daemon not reachable." >&2; exit 2; }

mkdir -p "$OUT" || exit 2
ts="$(date -u '+%Y%m%d-%H%M%SZ')"
rc=0

# Container ids in scope.
if [ -n "$PROJECT" ]; then
  mapfile -t IDS < <(docker ps -q --filter "label=com.docker.compose.project=$PROJECT")
else
  mapfile -t IDS < <(docker ps -q --filter "label=com.docker.compose.project")
fi
[ "${#IDS[@]}" -gt 0 ] || { echo "No running compose-managed containers found."; exit 0; }

cenv()  { docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$1"; }
val()   { cenv "$1" | sed -n "s/^$2=//p" | head -1; }
label() { docker inspect --format "{{index .Config.Labels \"$2\"}}" "$1"; }

for id in "${IDS[@]}"; do
  name="$(docker inspect --format '{{.Name}}' "$id" | sed 's#^/##')"
  image="$(docker inspect --format '{{.Config.Image}}' "$id")"
  proj="$(label "$id" com.docker.compose.project)"
  svc="$(label "$id" com.docker.compose.service)"
  base="$OUT/${proj:-nostack}-${svc:-$name}-$ts"

  case "$image" in
    *postgres*|*timescaledb*|*pgvecto*|*pgautoupgrade*)
      user="$(val "$id" POSTGRES_USER)"; user="${user:-postgres}"
      echo "postgres  $name  -> $base.sql.gz"
      [ "$DRY" -eq 1 ] && continue
      if docker exec "$id" pg_dumpall -U "$user" 2>/dev/null | gzip > "$base.sql.gz" && [ -s "$base.sql.gz" ]; then
        echo "  ok"
      else
        echo "  FAILED" >&2; rm -f "$base.sql.gz"; rc=1
      fi
      ;;
    *mariadb*|*mysql*|*percona*)
      pw="$(val "$id" MYSQL_ROOT_PASSWORD)"; pw="${pw:-$(val "$id" MARIADB_ROOT_PASSWORD)}"
      echo "mysql     $name  -> $base.sql.gz"
      [ "$DRY" -eq 1 ] && continue
      if docker exec -e MYSQL_PWD="$pw" "$id" \
           sh -c 'exec mysqldump --all-databases --single-transaction --routines --events -uroot' 2>/dev/null \
           | gzip > "$base.sql.gz" && [ -s "$base.sql.gz" ]; then
        echo "  ok"
      else
        echo "  FAILED" >&2; rm -f "$base.sql.gz"; rc=1
      fi
      ;;
    *redis*|*valkey*|*keydb*)
      echo "redis     $name  -> $base.rdb.gz"
      [ "$DRY" -eq 1 ] && continue
      if docker exec "$id" sh -c 'redis-cli SAVE >/dev/null && cat "$(redis-cli CONFIG GET dir | tail -1)/$(redis-cli CONFIG GET dbfilename | tail -1)"' 2>/dev/null \
           | gzip > "$base.rdb.gz" && [ -s "$base.rdb.gz" ]; then
        echo "  ok"
      else
        echo "  FAILED" >&2; rm -f "$base.rdb.gz"; rc=1
      fi
      ;;
    *)
      # SQLite: look for a *.sqlite/*.db file inside the container's mounts.
      dbfile="$(docker exec "$id" sh -c 'find / -maxdepth 6 -type f \( -name "*.sqlite" -o -name "*.sqlite3" -o -name "*.db" \) 2>/dev/null | head -1' 2>/dev/null || true)"
      if [ -n "$dbfile" ]; then
        echo "sqlite    $name  ($dbfile) -> $base.sqlite.gz"
        [ "$DRY" -eq 1 ] && continue
        if docker exec "$id" sh -c "command -v sqlite3 >/dev/null && sqlite3 '$dbfile' '.backup /tmp/_dump.sqlite' && cat /tmp/_dump.sqlite && rm -f /tmp/_dump.sqlite || cat '$dbfile'" 2>/dev/null \
             | gzip > "$base.sqlite.gz" && [ -s "$base.sqlite.gz" ]; then
          echo "  ok"
        else
          echo "  FAILED" >&2; rm -f "$base.sqlite.gz"; rc=1
        fi
      fi
      ;;
  esac
done

if [ "$DRY" -eq 0 ]; then
  ( cd "$OUT" && sha256sum ./*"-$ts".* > "SHA256SUMS-$ts" 2>/dev/null ) || true
fi
[ "$rc" -eq 0 ] && echo "done." || echo "one or more dumps failed." >&2
exit "$rc"
