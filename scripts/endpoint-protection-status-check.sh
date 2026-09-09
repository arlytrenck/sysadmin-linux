#!/usr/bin/env bash
#
# endpoint-protection-status-check.sh — report the presence and health of
# the host-level protections most distros ship but nobody checks after
# initial setup: SSH brute-force banning (fail2ban/sshguard), mandatory
# access control (SELinux/AppArmor), antivirus signatures (ClamAV), and
# audit logging (auditd). Flags what's missing, disabled, or stale.
#
# Absence of ClamAV or auditd is reported but not flagged — plenty of
# servers run without an on-host scanner or audit trail by design. A MAC
# framework or a brute-force jail that's missing, permissive, or empty
# is flagged, since those are on by default on most current distros and
# their absence is usually drift, not a decision. Read-only.
#
# Usage:
#   ./endpoint-protection-status-check.sh [-a MAX_SIG_AGE_DAYS] [-h]
#
# Options:
#   -a   Flag ClamAV signatures older than this many days (default 3)
#   -h   Show this help
#
# Exit codes:
#   0 - no findings
#   1 - at least one finding
#   2 - usage error

set -uo pipefail

SIG_MAX_AGE_DAYS=3

usage() { sed -n '2,/^[^#]/p' "$0" | sed '1{/^#$/d;}; $d; s/^# \{0,1\}//'; exit "${1:-0}"; }

while getopts ":a:h" opt; do
  case "$opt" in
    a) SIG_MAX_AGE_DAYS="$OPTARG" ;;
    h) usage 0 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage 2 ;;
    :) echo "Option -$OPTARG requires an argument" >&2; usage 2 ;;
  esac
done

flagged=0

is_active() { command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet "$1" 2>/dev/null; }

echo "=== Brute-force protection (fail2ban / sshguard) ==="
if command -v fail2ban-client >/dev/null 2>&1 && is_active fail2ban; then
  jails="$(fail2ban-client status 2>/dev/null | awk -F':[[:space:]]*' '/Jail list/ {print $2}')"
  jails="${jails## }"
  if [[ -z "$jails" ]]; then
    echo "  fail2ban active, no jails configured"
    echo "FLAG: fail2ban is running but has no jails — nothing is actually being banned"
    flagged=$((flagged+1))
  else
    echo "  fail2ban active. Jails: $jails"
    IFS=',' read -ra jail_arr <<< "$jails"
    for j in "${jail_arr[@]}"; do
      j="${j# }"
      [[ -z "$j" ]] && continue
      banned="$(fail2ban-client status "$j" 2>/dev/null | awk -F':[[:space:]]*' '/Currently banned/ {print $2}')"
      echo "    $j: currently banned ${banned:-0}"
    done
  fi
elif command -v sshguard >/dev/null 2>&1 && is_active sshguard; then
  echo "  sshguard active (fail2ban not present)"
elif command -v fail2ban-client >/dev/null 2>&1 || command -v sshguard >/dev/null 2>&1; then
  echo "FLAG: fail2ban or sshguard is installed but not running"
  flagged=$((flagged+1))
else
  echo "FLAG: neither fail2ban nor sshguard is active — SSH brute-force attempts are not rate-limited or banned"
  flagged=$((flagged+1))
fi

echo
echo "=== Mandatory access control (SELinux / AppArmor) ==="
if command -v getenforce >/dev/null 2>&1; then
  mode="$(getenforce 2>/dev/null)"
  echo "  SELinux mode: $mode"
  case "$mode" in
    Enforcing) ;;
    Permissive)
      echo "FLAG: SELinux is Permissive — violations are logged but not blocked"
      flagged=$((flagged+1))
      ;;
    *)
      echo "FLAG: SELinux is Disabled"
      flagged=$((flagged+1))
      ;;
  esac
elif command -v aa-status >/dev/null 2>&1; then
  aa_out="$(aa-status 2>/dev/null)"
  enforce_n="$(awk '/profiles are in enforce mode/ {print $1}' <<< "$aa_out")"
  complain_n="$(awk '/profiles are in complain mode/ {print $1}' <<< "$aa_out")"
  echo "  AppArmor: ${enforce_n:-0} profile(s) enforcing, ${complain_n:-0} in complain mode"
  if [[ "${enforce_n:-0}" -eq 0 ]]; then
    echo "FLAG: AppArmor is installed but no profiles are enforcing"
    flagged=$((flagged+1))
  fi
else
  echo "FLAG: neither SELinux nor AppArmor found — no mandatory access control in place"
  flagged=$((flagged+1))
fi

echo
echo "=== Antivirus signatures (ClamAV) ==="
if command -v freshclam >/dev/null 2>&1 || command -v clamscan >/dev/null 2>&1; then
  db_dir="/var/lib/clamav"
  newest_db="" ; newest_mtime=0
  if [[ -d "$db_dir" ]]; then
    while IFS= read -r f; do
      m=$(stat -c %Y "$f" 2>/dev/null) || continue
      (( m > newest_mtime )) && { newest_mtime=$m; newest_db=$f; }
    done < <(find "$db_dir" -maxdepth 1 -type f \( -name '*.cvd' -o -name '*.cld' \) 2>/dev/null)
  fi
  if [[ -n "$newest_db" ]]; then
    age_days=$(( ( $(date +%s) - newest_mtime ) / 86400 ))
    echo "  Newest signature DB: $(basename "$newest_db"), ${age_days}d old"
    if (( age_days > SIG_MAX_AGE_DAYS )); then
      echo "FLAG: ClamAV signatures are ${age_days}d old, past the ${SIG_MAX_AGE_DAYS}d limit"
      flagged=$((flagged+1))
    fi
  else
    echo "FLAG: ClamAV is installed but no signature database found in $db_dir"
    flagged=$((flagged+1))
  fi
  if is_active clamav-daemon || is_active clamd; then
    echo "  On-access daemon: active"
  else
    echo "  On-access daemon: not running (on-demand scanning via clamscan only)"
  fi
else
  echo "  Not installed. Informational only: many servers run without an on-host scanner by design."
fi

echo
echo "=== Audit logging (auditd) ==="
if command -v auditctl >/dev/null 2>&1; then
  if is_active auditd; then
    rule_count="$(auditctl -l 2>/dev/null | grep -vc '^No rules')"
    echo "  auditd active, $rule_count rule(s) loaded"
    if [[ "$rule_count" -eq 0 ]]; then
      echo "FLAG: auditd is running with zero rules loaded — nothing is actually being audited"
      flagged=$((flagged+1))
    fi
  else
    echo "FLAG: auditd is installed but not running"
    flagged=$((flagged+1))
  fi
else
  echo "  Not installed. Informational only: auditd is a deliberate addition, not a distro default."
fi

echo
if (( flagged )); then
  echo "RESULT: $flagged finding(s)."
  exit 1
fi
echo "RESULT: no findings."
