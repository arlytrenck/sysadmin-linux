#!/usr/bin/env bash
#
# sudo-access-audit.sh — enumerate every local account with a path to root
# and flag the grants that make that path quieter than it should be.
#
# Root access is rarely granted once and then reviewed. It accretes: a
# NOPASSWD line added so a deploy job would stop hanging, a second UID-0
# account created during a migration and never removed, a wildcard in a
# command spec that turns a narrow grant into a full shell. This walks
# the sudoers stack, the administrative groups, and passwd, and reports
# what it finds. Read-only — it changes nothing.
#
# Run it as root: most of /etc/sudoers.d is mode 0440 and invisible
# otherwise, and a partial audit is worse than no audit.
#
# Usage:
#   ./sudo-access-audit.sh [-a USER[,USER...]] [-v]
#
# Options:
#   -a   Comma-separated allowlist of accounts expected to hold root
#        access. Anything else with a path to root is flagged. Omit it
#        to inventory access without flagging on identity.
#   -v   Verbose: print every sudoers rule parsed, not just flagged ones
#   -h   Show this help
#
# Exit codes:
#   0 - no findings
#   1 - at least one finding
#   2 - usage error, or no sudoers file was readable

set -uo pipefail

ALLOWLIST=""
VERBOSE=0

usage() { sed -n '2,/^[^#]/p' "$0" | sed '1{/^#$/d;}; $d; s/^# \{0,1\}//'; exit "${1:-0}"; }

while getopts ":a:vh" opt; do
  case "$opt" in
    a) ALLOWLIST="$OPTARG" ;;
    v) VERBOSE=1 ;;
    h) usage 0 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage 2 ;;
    :) echo "Option -$OPTARG requires an argument" >&2; usage 2 ;;
  esac
done

flagged=0

# With no allowlist every principal counts as expected, so the script
# degrades to an inventory rather than crying wolf on a host it knows
# nothing about.
allowed() {
  local who="$1" entry
  local -a list
  [[ -z "$ALLOWLIST" ]] && return 0
  # Compare with the %group / +netgroup sigil stripped from both sides, so
  # '-a sudo' and '-a %sudo' both match a '%sudo' rule.
  who="${who#%}"; who="${who#+}"
  IFS=',' read -ra list <<< "$ALLOWLIST"
  for entry in "${list[@]}"; do
    entry="${entry#"${entry%%[![:space:]]*}"}"
    entry="${entry%"${entry##*[![:space:]]}"}"
    entry="${entry#%}"; entry="${entry#+}"
    [[ "$who" == "$entry" ]] && return 0
  done
  return 1
}

# root and the distro's own admin group are *supposed* to hold blanket root.
# Reporting that as a finding on every host trains people to ignore the tool.
is_standard_admin() {
  case "$1" in
    root|%sudo|%wheel|%admin) return 0 ;;
    *) return 1 ;;
  esac
}

# A locked account that still holds root is worth knowing about: the
# password is gone, but an SSH key or a sudo rule may still work fine.
account_state() {
  local state
  state="$(passwd -S "$1" 2>/dev/null | awk '{print $2}')"
  case "$state" in
    L|LK) echo "password is locked" ;;
    NP)   echo "has NO PASSWORD SET" ;;
    *)    echo "" ;;
  esac
}

echo "=== UID 0 accounts ==="
while IFS=: read -r user _ uid _ _ _ shell; do
  [[ "$uid" == "0" ]] || continue
  if [[ "$user" == "root" ]]; then
    echo "  root (expected), shell $shell"
  else
    echo "FLAG: $user has UID 0 — a full second root account, not a sudo grant (shell $shell)"
    flagged=$((flagged+1))
  fi
done < <(getent passwd)

echo
echo "=== Administrative group membership ==="
found_group=0
for grp in sudo wheel admin; do
  gline="$(getent group "$grp" 2>/dev/null)" || continue
  [[ -n "$gline" ]] || continue
  found_group=1
  gid="$(cut -d: -f3 <<< "$gline")"
  members="${gline##*:}"

  # Secondary members come from the group line. Anyone whose *primary* GID
  # is this group never appears there, which is a classic way to miss an
  # admin account during a review.
  primaries=""
  while IFS=: read -r puser _ _ pgid _; do
    [[ "$pgid" == "$gid" ]] && primaries+="${primaries:+,}$puser"
  done < <(getent passwd)

  all="$members"
  [[ -n "$primaries" ]] && all="${all:+$all,}$primaries"

  if [[ -z "$all" ]]; then
    echo "  $grp (gid $gid): empty"
    continue
  fi
  echo "  $grp (gid $gid): $all"

  IFS=',' read -ra mlist <<< "$all"
  for m in "${mlist[@]}"; do
    [[ -n "$m" ]] || continue
    if ! allowed "$m"; then
      echo "FLAG: $m is in '$grp' but is not on the allowlist"
      flagged=$((flagged+1))
    fi
    state="$(account_state "$m")"
    if [[ -n "$state" ]]; then
      echo "FLAG: $m is in '$grp' and $state — check authorized_keys before assuming it is inert"
      flagged=$((flagged+1))
    fi
  done
done
(( found_group )) || echo "  none of sudo/wheel/admin exist on this host"

echo
echo "=== sudoers rules ==="
sudoers_files=()
[[ -r /etc/sudoers ]] && sudoers_files+=("/etc/sudoers")
if [[ -d /etc/sudoers.d ]]; then
  while IFS= read -r f; do
    [[ -r "$f" ]] && sudoers_files+=("$f")
  done < <(find /etc/sudoers.d -maxdepth 1 -type f ! -name '*~' ! -name '*.bak' ! -name '*.dpkg-*' ! -name '*.rpm*' 2>/dev/null | sort)
fi

if (( ${#sudoers_files[@]} == 0 )); then
  echo "No sudoers file was readable. Re-run as root." >&2
  exit 2
fi

# GTFOBins in one regex. Any of these, granted as root, hands back a root
# shell or arbitrary root file access. The grant reads as narrow; it isn't.
# Bash will not parse a bare ')' inside an unquoted =~ pattern, so both of
# these live in variables and are matched unquoted from there.
all_re='(^|[[:space:]:)])ALL[[:space:]]*$'
escape_re='(^|/)(ba|z|k|da|c|tc)?sh($|[[:space:]])|(^|/)(vi|vim|nvim|view|nano|emacs|ed|sed|less|more|man|find|awk|gawk|mawk|perl|python[0-9.]*|ruby|lua|node|tar|cpio|rsync|zip|unzip|git|docker|podman|systemctl|journalctl|mount|env|nmap|socat|tee|dd|apt|apt-get|yum|dnf|pip[0-9.]*)($|[[:space:]])'

for f in "${sudoers_files[@]}"; do
  echo "--- $f ---"
  perm="$(stat -c '%a %U:%G' "$f" 2>/dev/null || echo '?? ?:?')"
  case "$perm" in
    "440 root:root"|"400 root:root") ;;
    *) echo "FLAG: $f is $perm — sudoers files should be 0440 root:root"; flagged=$((flagged+1)) ;;
  esac

  while IFS= read -r raw; do
    line="${raw#"${raw%%[![:space:]]*}"}"
    [[ -z "$line" ]] && continue
    case "$line" in
      '#'*) continue ;;
    esac

    case "$line" in
      Defaults*)
        (( VERBOSE )) && echo "        $line"
        if [[ "$line" == *'!authenticate'* ]]; then
          echo "FLAG: $f: '!authenticate' — sudo stops asking for a password at all"
          flagged=$((flagged+1))
        fi
        if [[ "$line" == *'timestamp_timeout=-1'* ]]; then
          echo "FLAG: $f: timestamp_timeout=-1 — an authenticated sudo session never expires"
          flagged=$((flagged+1))
        fi
        if [[ "$line" == *'!log_'* || "$line" == *'!syslog'* ]]; then
          echo "FLAG: $f: sudo logging disabled by '$line'"
          flagged=$((flagged+1))
        fi
        continue
        ;;
      User_Alias*|Runas_Alias*|Host_Alias*|Cmnd_Alias*|@include*|includedir*)
        (( VERBOSE )) && echo "        $line"
        continue
        ;;
    esac

    # Not a Defaults or alias line, so treat it as a grant: the principal,
    # then the host=(runas) command spec after the first '='.
    principal="${line%%[[:space:]]*}"
    spec="${line#*=}"
    (( VERBOSE )) && echo "        $line"

    # Strip the %group / +netgroup sigil before matching the allowlist.
    check_name="${principal#%}"
    check_name="${check_name#+}"

    if ! allowed "$check_name"; then
      echo "FLAG: $f: '$principal' holds a sudoers rule but is not on the allowlist"
      flagged=$((flagged+1))
    fi

    if [[ "$spec" == *NOPASSWD* ]]; then
      echo "FLAG: $f: '$principal' has NOPASSWD — root with no reauthentication"
      flagged=$((flagged+1))
    fi

    if [[ "$spec" =~ $all_re ]]; then
      if is_standard_admin "$principal"; then
        echo "        $principal may run ALL commands as root (the stock arrangement)"
      else
        echo "FLAG: $f: '$principal' may run ALL commands as root"
        flagged=$((flagged+1))
      fi
    fi

    if [[ "$spec" == *'*'* ]]; then
      echo "FLAG: $f: '$principal' has a wildcard in its command spec — argument injection widens this to a full shell"
      flagged=$((flagged+1))
    fi

    cmds="${spec#*)}"
    if [[ "$cmds" =~ $escape_re ]]; then
      echo "FLAG: $f: '$principal' is granted an interpreter, archiver, or editor that can shell out — root-equivalent in practice"
      flagged=$((flagged+1))
    fi
  done < "$f"
done

echo
if (( flagged )); then
  echo "RESULT: $flagged finding(s). Review each one before dismissing it."
  exit 1
fi
echo "RESULT: no findings."
