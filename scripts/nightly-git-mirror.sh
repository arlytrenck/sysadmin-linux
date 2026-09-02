#!/usr/bin/env bash
#
# nightly-git-mirror.sh — for each git working tree given, stage everything,
#   commit if there's drift, and push. Built to run from cron so config that
#   lives in git (compose files, /etc snapshots, dashboards) stays mirrored
#   off-host without anyone remembering to commit.
#
# Non-fatal by design: a network blip or one bad repo must not abort the run.
#
# Usage:
#   ./nightly-git-mirror.sh [-m "MESSAGE"] [-b BRANCH] DIR [DIR ...]
#   ./nightly-git-mirror.sh -f LIST_FILE           # DIRs one per line
#
# Options:
#   -m MSG   Commit message (default: "mirror: <date>"). "%d" is replaced
#            with the current date.
#   -b REF   Branch/ref to push to (default: the repo's current branch).
#   -f FILE  Read directories from FILE (one per line, # comments allowed).
#   -h       Show this help.
#
# Each repo must already have an `origin` remote and working push auth
# (deploy key with `IdentitiesOnly`, ssh-agent, etc.). Commits use the repo's
# own user.name/user.email if set, otherwise a "git-mirror" identity.
#
# Exit codes: 0 = every repo OK / clean, 1 = one or more repos had an error

set -uo pipefail

MSG='mirror: %d' ; BRANCH="" ; LISTFILE=""
usage() { grep -E '^#( |$)' "$0" | sed '1d; s/^# \{0,1\}//'; exit "${1:-0}"; }

while getopts ":m:b:f:h" opt; do
  case "$opt" in
    m) MSG="$OPTARG" ;;
    b) BRANCH="$OPTARG" ;;
    f) LISTFILE="$OPTARG" ;;
    h) usage 0 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage 2 ;;
    :) echo "Option -$OPTARG requires an argument" >&2; usage 2 ;;
  esac
done
shift $((OPTIND - 1))

DIRS=("$@")
if [ -n "$LISTFILE" ]; then
  [ -r "$LISTFILE" ] || { echo "Cannot read list file: $LISTFILE" >&2; exit 2; }
  while IFS= read -r line; do
    line="${line%%#*}"; line="$(printf '%s' "$line" | xargs)"
    [ -n "$line" ] && DIRS+=("$line")
  done < "$LISTFILE"
fi
[ "${#DIRS[@]}" -gt 0 ] || { echo "No directories given." >&2; usage 2; }

commit_msg="${MSG//%d/$(date -u '+%Y-%m-%d')}"
rc=0

for d in "${DIRS[@]}"; do
  echo "== $d"
  if [ ! -d "$d/.git" ]; then echo "  ! not a git repo"; rc=1; continue; fi

  if ! git -C "$d" remote get-url origin >/dev/null 2>&1; then
    echo "  ! no 'origin' remote"; rc=1; continue
  fi

  ref="$BRANCH"
  [ -z "$ref" ] && ref="$(git -C "$d" symbolic-ref --short -q HEAD || echo main)"

  name="$(git -C "$d" config user.name  || echo 'git-mirror')"
  email="$(git -C "$d" config user.email || echo 'git-mirror@localhost')"

  git -C "$d" add -A
  if git -C "$d" diff --cached --quiet; then
    echo "  clean (nothing to commit)"
  else
    if git -C "$d" -c user.name="$name" -c user.email="$email" commit -q -m "$commit_msg"; then
      echo "  committed: $commit_msg"
    else
      echo "  ! commit failed"; rc=1; continue
    fi
  fi

  if git -C "$d" push -q origin "HEAD:$ref" 2>/dev/null; then
    echo "  pushed -> origin/$ref"
  else
    echo "  ! push failed (auth? network? diverged?)"; rc=1
  fi
done

echo
[ "$rc" -eq 0 ] && echo "All repos mirrored." || echo "One or more repos had an error." >&2
exit "$rc"
