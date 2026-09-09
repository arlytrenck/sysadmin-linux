#!/usr/bin/env bash
#
# luks-encryption-audit.sh — report which mounted filesystems are backed by
# LUKS and which are sitting on the disk in the clear, then audit the
# headers of the ones that are encrypted.
#
# "The server is encrypted" usually means one volume is. The pattern that
# actually bites is a second data disk added later, a swap partition that
# was never encrypted (memory pages land there in plaintext), or a LUKS
# header still on LUKS1 with a PBKDF2 key derivation that a GPU chews
# through. This also counts keyslots: a slot you cannot account for is a
# key someone else may still hold. Read-only — it changes nothing.
#
# Run it as root. cryptsetup luksDump needs read access to the header,
# and without it the audit degrades to a topology listing.
#
# Usage:
#   ./luks-encryption-audit.sh [-a MOUNT[,MOUNT...]] [-v]
#
# Options:
#   -a   Comma-separated mountpoints allowed to be unencrypted
#        (default: /boot,/boot/efi — an unencrypted ESP is unavoidable)
#   -v   Verbose: also print the full luksDump for every container
#   -h   Show this help
#
# Exit codes:
#   0 - no findings
#   1 - at least one finding
#   2 - usage error, or lsblk is unavailable

set -uo pipefail

ALLOW_PLAIN="/boot,/boot/efi"
VERBOSE=0

usage() { sed -n '2,/^[^#]/p' "$0" | sed '1{/^#$/d;}; $d; s/^# \{0,1\}//'; exit "${1:-0}"; }

while getopts ":a:vh" opt; do
  case "$opt" in
    a) ALLOW_PLAIN="$OPTARG" ;;
    v) VERBOSE=1 ;;
    h) usage 0 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage 2 ;;
    :) echo "Option -$OPTARG requires an argument" >&2; usage 2 ;;
  esac
done

command -v lsblk >/dev/null 2>&1 || { echo "lsblk not found (install util-linux)." >&2; exit 2; }

flagged=0

declare -A DEV_TYPE     # kernel name -> type (disk, part, crypt, lvm, raid)
declare -A DEV_PARENT   # kernel name -> parent kernel name
declare -A DEV_FSTYPE   # kernel name -> filesystem type
declare -A DEV_PATH     # kernel name -> /dev path

# lsblk -P emits KEY="value" pairs. Parsed by hand rather than with eval:
# eval on a line containing PATH="..." would replace the shell's own $PATH.
# The leading space makes ' NAME="' unambiguous against ' PKNAME="'.
kv() {
  local line=" $1" key="$2" rest pat
  pat=" ${key}=\""
  rest="${line#*"$pat"}"
  [[ "$rest" == "$line" ]] && return 0
  printf '%s' "${rest%%\"*}"
}

while IFS= read -r line; do
  name="$(kv "$line" NAME)"
  [[ -n "$name" ]] || continue
  DEV_TYPE["$name"]="$(kv "$line" TYPE)"
  DEV_PARENT["$name"]="$(kv "$line" PKNAME)"
  DEV_FSTYPE["$name"]="$(kv "$line" FSTYPE)"
  kpath="$(kv "$line" PATH)"
  DEV_PATH["$name"]="${kpath:-/dev/$name}"
done < <(lsblk -P -o NAME,PATH,TYPE,FSTYPE,PKNAME 2>/dev/null)

# Walk the device tree upward from a leaf. If any ancestor is a dm-crypt
# mapping, everything stacked on top of it is encrypted at rest.
is_encrypted() {
  local dev="$1" hops=0
  while [[ -n "$dev" && $hops -lt 12 ]]; do
    [[ "${DEV_TYPE[$dev]:-}" == "crypt" ]] && return 0
    dev="${DEV_PARENT[$dev]:-}"
    hops=$((hops+1))
  done
  return 1
}

plain_allowed() {
  local mp="$1" entry
  local -a list
  IFS=',' read -ra list <<< "$ALLOW_PLAIN"
  for entry in "${list[@]}"; do
    [[ "$mp" == "$entry" ]] && return 0
  done
  return 1
}

echo "=== Mounted filesystems ==="
printf '  %-24s %-10s %-22s %s\n' "MOUNTPOINT" "FSTYPE" "SOURCE" "AT REST"

# findmnt gives the real backing source; /proc/mounts is the fallback. Only
# real block-backed filesystems are interesting, so pseudo types are skipped.
while IFS=' ' read -r src mp fstype; do
  case "$fstype" in
    tmpfs|devtmpfs|proc|sysfs|cgroup|cgroup2|devpts|securityfs|debugfs|tracefs|\
    pstore|bpf|configfs|fusectl|hugetlbfs|mqueue|autofs|squashfs|overlay|\
    efivarfs|binfmt_misc|ramfs|nsfs|rpc_pipefs|fuse.*|nfs*|cifs|smb3|zfs) continue ;;
  esac
  [[ "$src" == /dev/* ]] || continue

  kname="$(basename "$(readlink -f "$src" 2>/dev/null || echo "$src")")"
  if is_encrypted "$kname"; then
    printf '  %-24s %-10s %-22s %s\n' "$mp" "$fstype" "$src" "LUKS"
  else
    printf '  %-24s %-10s %-22s %s\n' "$mp" "$fstype" "$src" "PLAINTEXT"
    if ! plain_allowed "$mp"; then
      echo "FLAG: $mp ($src) is not encrypted at rest"
      flagged=$((flagged+1))
    fi
  fi
done < <(findmnt -rn -o SOURCE,TARGET,FSTYPE 2>/dev/null || awk '{print $1, $2, $3}' /proc/mounts)

echo
echo "=== Swap ==="
if [[ -r /proc/swaps ]] && [[ "$(wc -l < /proc/swaps)" -gt 1 ]]; then
  while read -r sname stype _; do
    [[ "$sname" == "Filename" ]] && continue
    kname="$(basename "$(readlink -f "$sname" 2>/dev/null || echo "$sname")")"
    if [[ "$stype" == "file" ]]; then
      # A swapfile inherits whatever the filesystem underneath it has.
      echo "  $sname (file) — inherits the encryption of its filesystem"
    elif is_encrypted "$kname"; then
      echo "  $sname — LUKS"
    else
      echo "  $sname — PLAINTEXT"
      echo "FLAG: swap on $sname is not encrypted — anything paged out lands on disk in the clear"
      flagged=$((flagged+1))
    fi
  done < /proc/swaps
else
  echo "  no swap active"
fi

echo
echo "=== LUKS containers ==="
if ! command -v cryptsetup >/dev/null 2>&1; then
  echo "  cryptsetup not installed — skipping header audit"
else
  found_luks=0
  for name in "${!DEV_FSTYPE[@]}"; do
    [[ "${DEV_FSTYPE[$name]}" == "crypto_LUKS" ]] || continue
    found_luks=1
    dev="${DEV_PATH[$name]}"
    echo "--- $dev ---"

    dump="$(cryptsetup luksDump "$dev" 2>/dev/null)"
    if [[ -z "$dump" ]]; then
      echo "FLAG: could not read the LUKS header on $dev (run as root)"
      flagged=$((flagged+1))
      continue
    fi
    (( VERBOSE )) && printf '%s\n' "$dump"

    version="$(awk -F': *' '/^Version:/ {print $2; exit}' <<< "$dump")"
    echo "  Version: ${version:-unknown}"
    if [[ "$version" == "1" ]]; then
      echo "FLAG: $dev is LUKS1 — no header backup area and PBKDF2 only; convert to LUKS2"
      flagged=$((flagged+1))
    fi

    # Scoped to the Keyslots block on purpose: LUKS2 also lists a Digests
    # section whose entries are legitimately named pbkdf2, and matching that
    # would flag every healthy volume on the host.
    keyslot_block="$(awk '/^Keyslots:/{f=1;next} /^(Tokens|Digests|Area):/{f=0} f' <<< "$dump")"
    if grep -qiE '^[[:space:]]*PBKDF:[[:space:]]*pbkdf2' <<< "$keyslot_block"; then
      echo "FLAG: $dev has a keyslot using PBKDF2 — argon2id resists GPU cracking far better"
      flagged=$((flagged+1))
    fi

    # LUKS2 prints an indented 'Cipher:' per keyslot; LUKS1 splits the name
    # and the mode across two top-level lines.
    cipher="$(awk -F': *' '/^[[:space:]]*Cipher:/ {print $2; exit}' <<< "$dump")"
    if [[ -z "$cipher" ]]; then
      cname="$(awk -F': *' '/^Cipher name:/ {print $2; exit}' <<< "$dump")"
      cmode="$(awk -F': *' '/^Cipher mode:/ {print $2; exit}' <<< "$dump")"
      [[ -n "$cname" ]] && cipher="$cname-$cmode"
    fi
    echo "  Cipher: ${cipher:-unknown}"
    if [[ "$cipher" == *cbc* ]]; then
      echo "FLAG: $dev uses a CBC mode cipher — XTS is the current default for block storage"
      flagged=$((flagged+1))
    fi

    if [[ "$version" == "1" ]]; then
      slots="$(grep -c 'Key Slot [0-7]: ENABLED' <<< "$dump")"
    else
      slots="$(awk '/^Keyslots:/,/^Tokens:|^Digests:/' <<< "$dump" | grep -cE '^[[:space:]]+[0-9]+: luks2')"
    fi
    echo "  Keyslots in use: ${slots:-0}"
    if [[ "${slots:-0}" -gt 2 ]]; then
      echo "FLAG: $dev has $slots keyslots in use — each one is a key that still unlocks this volume"
      flagged=$((flagged+1))
    fi
    if [[ "${slots:-0}" -eq 0 ]]; then
      echo "FLAG: $dev reports no enabled keyslots — the header may be damaged"
      flagged=$((flagged+1))
    fi
  done
  (( found_luks )) || echo "  no LUKS containers found on this host"
fi

echo
echo "=== /etc/crypttab ==="
if [[ -r /etc/crypttab ]]; then
  while IFS= read -r raw; do
    line="${raw#"${raw%%[![:space:]]*}"}"
    [[ -z "$line" ]] && continue
    case "$line" in
      '#'*) continue ;;
    esac
    read -r ct_name ct_dev ct_key ct_opts <<< "$line"
    echo "  $ct_name -> $ct_dev (key: ${ct_key:-none}, opts: ${ct_opts:-none})"

    # A keyfile that lives on an unencrypted filesystem, or is readable by
    # anyone but root, is the whole secret sitting next to the lock.
    if [[ -n "$ct_key" && "$ct_key" != "none" && "$ct_key" != "-" && -e "$ct_key" ]]; then
      kperm="$(stat -c '%a' "$ct_key" 2>/dev/null || echo "??")"
      if [[ "$kperm" != "400" && "$kperm" != "600" ]]; then
        echo "FLAG: keyfile $ct_key is mode $kperm — it should be 0400 root:root"
        flagged=$((flagged+1))
      fi
      kname="$(basename "$(readlink -f "$(df --output=source "$ct_key" 2>/dev/null | tail -1)" 2>/dev/null)")"
      if [[ -n "$kname" ]] && ! is_encrypted "$kname"; then
        echo "FLAG: keyfile $ct_key sits on an unencrypted filesystem — the key travels with the disk"
        flagged=$((flagged+1))
      fi
    fi
  done < /etc/crypttab
else
  echo "  /etc/crypttab not readable or not present"
fi

echo
if (( flagged )); then
  echo "RESULT: $flagged finding(s)."
  exit 1
fi
echo "RESULT: no findings."
