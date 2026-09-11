#!/usr/bin/env bash
#
# ssh-key-audit.sh — audit authorized_keys across all local users.
#
# Flags weak key types/sizes, keys with no comment (harder to trace back to
# an owner), and the same public key authorized for more than one account
# (a shared key defeats per-user accountability). Read-only.
#
# Best run as root: home directories are normally 700, so without it this
# can only see the invoking user's own authorized_keys and silently skips
# everyone else's. It still runs unprivileged and says so, rather than
# refusing outright — a partial audit of just your own account is still
# useful, it just isn't the whole picture.
#
# Usage: ./ssh-key-audit.sh [-v]
#   -v    verbose: also print every key found, not just flagged ones
#
set -euo pipefail

usage() { sed -n '2,/^[^#]/p' "$0" | sed '1{/^#$/d;}; $d; s/^# \{0,1\}//'; exit "${1:-0}"; }

VERBOSE=0
while getopts "vh" opt; do
  case "$opt" in
    v) VERBOSE=1 ;;
    h) usage 0 ;;
    *) usage 1 ;;
  esac
done

declare -A seen_keys   # fingerprint -> "user1 user2 ..."
flagged=0

if [ "$EUID" -ne 0 ]; then
  echo "Heads up: not running as root — home directories are normally" >&2
  echo "700 and unreadable by anyone else, so this will silently skip" >&2
  echo "most other users' authorized_keys. Run with sudo for full coverage." >&2
  echo >&2
fi

echo "=== SSH authorized_keys audit ==="

while IFS=: read -r user _ uid _ _ home shell; do
  [ "$uid" -lt 1000 ] && [ "$uid" -ne 0 ] && continue
  case "$shell" in */nologin|*/false|"") continue ;; esac

  akfile="$home/.ssh/authorized_keys"
  [ -f "$akfile" ] || continue

  # Directory/file permission check
  ssh_dir="$home/.ssh"
  dir_perm=$(stat -c '%a' "$ssh_dir" 2>/dev/null || echo "??")
  file_perm=$(stat -c '%a' "$akfile" 2>/dev/null || echo "??")
  if [ "$dir_perm" != "700" ]; then
    echo "[PERM]  $user: ~/.ssh is mode $dir_perm (expected 700)"
    flagged=$((flagged+1))
  fi
  if [ "$file_perm" != "600" ] && [ "$file_perm" != "644" ]; then
    echo "[PERM]  $user: authorized_keys is mode $file_perm (expected 600)"
    flagged=$((flagged+1))
  fi

  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"   # trim leading whitespace
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac

    keytype=$(awk '{print $1}' <<< "$line")
    comment=$(awk '{ $1=""; $2=""; print $0 }' <<< "$line" | sed 's/^ *//')
    fp=$(ssh-keygen -lf /dev/stdin <<< "$line" 2>/dev/null | awk '{print $2}') || fp="unparseable"

    [ "$VERBOSE" -eq 1 ] && echo "        $user: $keytype ${comment:-<no comment>}"

    case "$keytype" in
      ssh-rsa)
        bits=$(ssh-keygen -lf /dev/stdin <<< "$line" 2>/dev/null | awk '{print $1}')
        if [ -n "$bits" ] && [ "$bits" -lt 2048 ]; then
          echo "[WEAK]  $user: RSA key is only $bits bits"
          flagged=$((flagged+1))
        fi
        ;;
      ssh-dss)
        echo "[WEAK]  $user: DSA key present — deprecated, should be replaced"
        flagged=$((flagged+1))
        ;;
    esac

    if [ -z "$comment" ]; then
      echo "[NOTE]  $user: key has no comment — hard to trace ownership ($keytype ${fp})"
    fi

    if [ "$fp" != "unparseable" ]; then
      if [ -n "${seen_keys[$fp]:-}" ]; then
        echo "[SHARED] key $fp is authorized for both '${seen_keys[$fp]}' and '$user'"
        flagged=$((flagged+1))
      fi
      seen_keys[$fp]="${seen_keys[$fp]:-} $user"
    fi
  done < "$akfile"
done < /etc/passwd

echo ""
if [ "$flagged" -eq 0 ]; then
  if [ "$EUID" -ne 0 ]; then
    echo "No issues found in the users this could read (not running as root — see heads-up above)."
  else
    echo "No issues found."
  fi
else
  echo "$flagged issue(s) flagged above."
fi

exit 0
