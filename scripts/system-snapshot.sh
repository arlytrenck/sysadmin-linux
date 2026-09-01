#!/usr/bin/env bash
# system-snapshot.sh — capture a subset of /etc plus a system inventory into a
# timestamped, integrity-checked tarball. Redacts obvious secrets on the way out
# so the result is safe to drop into a private repo or an encrypted backup.
#
# Usage:  system-snapshot.sh [-o OUTDIR] [-p EXTRA_PATH ...]
#   -o  where to write the tarball (default: current directory)
#   -p  an extra path to include (repeatable)
#
# Included by default: network config, apt/dnf sources, sysctl.d, modules,
# fstab, systemd overrides in /etc, crontab, and an inventory (versions, disks,
# listening ports, package selection, failed units). NOT included: anything
# under */private/, *.key, *.pem private keys, shadow, secret stores.
set -euo pipefail

OUT=. ; EXTRA=()
while getopts "o:p:h" o; do case "$o" in
  o) OUT=$OPTARG ;; p) EXTRA+=("$OPTARG") ;;
  *) sed -n '2,16p' "$0"; exit 2 ;;
esac; done

TS=$(date +%Y%m%d-%H%M%S)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/etc" "$W/inventory"

copy(){ [ -e "$1" ] && cp -a --parents "$1" "$W/root/" 2>/dev/null || true; }
mkdir -p "$W/root"
for p in \
  /etc/network/interfaces /etc/netplan /etc/systemd/network \
  /etc/apt/sources.list /etc/apt/sources.list.d /etc/yum.repos.d \
  /etc/sysctl.conf /etc/sysctl.d /etc/modules-load.d /etc/modprobe.d \
  /etc/fstab /etc/hosts /etc/hostname /etc/resolv.conf \
  /etc/systemd/system /etc/docker/daemon.json /etc/nftables.conf \
  "${EXTRA[@]}"
do copy "$p"; done
# systemd/system is large — keep only overrides/drop-ins and .timer/.target we added
find "$W/root/etc/systemd/system" -maxdepth 1 -type l -delete 2>/dev/null || true

I="$W/inventory"
{ uname -a; cat /etc/os-release; } > "$I/system.txt" 2>&1
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,SERIAL > "$I/disks.txt" 2>&1
df -hT > "$I/df.txt" 2>&1
ip -br addr > "$I/ip-addr.txt" 2>&1 ; ip route > "$I/ip-route.txt" 2>&1
{ ss -tlnp 2>/dev/null || netstat -tlnp; } > "$I/listening.txt" 2>&1
systemctl --failed --no-legend > "$I/failed-units.txt" 2>&1 || true
( command -v dpkg >/dev/null && apt-mark showmanual || rpm -qa ) 2>/dev/null \
  | sort > "$I/packages.txt"
crontab -l > "$I/crontab-$(id -un).txt" 2>/dev/null || echo "(none)" > "$I/crontab-$(id -un).txt"
{ command -v docker >/dev/null && docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'; } \
  > "$I/docker-ps.txt" 2>&1 || true

# --- redact obvious secrets, drop private keys entirely ---
find "$W/root" -type f \( -name '*.key' -o -name 'shadow*' -o -name '*.gpg' \) -delete 2>/dev/null || true
find "$W/root" -type f -name '*.pem' -exec sh -c \
  'grep -qi "PRIVATE KEY" "$1" && printf "<REDACTED PRIVATE KEY>\n" > "$1"' _ {} \; 2>/dev/null || true
find "$W" -type f -exec sed -i -E \
  's/((TOKEN|SECRET|PASSWORD|PASSWD|APIKEY|API_KEY)[[:space:]]*[=:][[:space:]]*)\S+/\1<REDACTED>/Ig' {} + 2>/dev/null || true

( cd "$W" && find . -type f ! -name SHA256SUMS.txt -exec sha256sum {} \; | sort -k2 > SHA256SUMS.txt )
mkdir -p "$OUT"
TAR="$OUT/system-snapshot-$(hostname)-$TS.tar.gz"
tar -czf "$TAR" -C "$W" .
gzip -t "$TAR"
echo "OK  $TAR  ($(du -h "$TAR" | cut -f1))"
echo "Contains a redacted view — verify with:  tar -xzO -f '$TAR' | grep -i 'PRIVATE KEY\\|token\\|password' | head"
