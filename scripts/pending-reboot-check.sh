#!/usr/bin/env bash
#
# pending-reboot-check.sh - detect whether a host is waiting on a reboot
#   to pick up an installed kernel or library update.
#
# Checks, in order:
#   - /var/run/reboot-required (Debian/Ubuntu, set by unattended-upgrades
#     or apt when a reboot-requiring package was updated)
#   - `needs-restarting -r` (RHEL/CentOS/Fedora, from yum-utils/dnf-utils)
#   - running kernel version vs. newest installed kernel package
#   - `needrestart -b` if installed (reports stale libraries held open by
#     running processes, e.g. after a libssl update, without needing a
#     full reboot in many cases)
#
# Usage: ./pending-reboot-check.sh [-h]
#
# Exit codes:
#   0 - no reboot indicators found
#   1 - reboot recommended/required
#   2 - could not determine (no supported indicator available)

set -uo pipefail

usage() {
    echo "Usage: $0 [-h]"
    echo "  Reports whether this host is waiting on a reboot."
    exit 0
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage

found_indicator=false
reboot_needed=false

echo "=== Distro reboot-required markers ==="
if [[ -f /var/run/reboot-required ]]; then
    found_indicator=true
    reboot_needed=true
    echo "REQUIRED: /var/run/reboot-required is present"
    if [[ -f /var/run/reboot-required.pkgs ]]; then
        echo "  Packages that triggered it:"
        sed 's/^/    /' /var/run/reboot-required.pkgs
    fi
elif command -v needs-restarting >/dev/null 2>&1; then
    found_indicator=true
    if needs-restarting -r >/dev/null 2>&1; then
        echo "OK: needs-restarting -r reports no reboot required"
    else
        reboot_needed=true
        echo "REQUIRED: needs-restarting -r reports a reboot is required"
    fi
else
    echo "No distro-native reboot-required marker found on this system."
fi
echo ""

echo "=== Running kernel vs. installed kernel packages ==="
running_kernel=$(uname -r)
echo "Running kernel: $running_kernel"

latest_installed=""
if command -v dpkg-query >/dev/null 2>&1; then
    latest_installed=$(dpkg-query -W -f='${Package} ${Version}\n' 2>/dev/null \
        | awk '$1 ~ /^linux-image-[0-9]/ {print $1}' | sed 's/^linux-image-//' \
        | sort -V | tail -n1)
elif command -v rpm >/dev/null 2>&1; then
    latest_installed=$(rpm -q kernel --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' 2>/dev/null \
        | sort -V | tail -n1)
fi

if [[ -n "$latest_installed" ]]; then
    found_indicator=true
    if [[ "$latest_installed" == "$running_kernel" ]]; then
        echo "OK: running kernel matches newest installed kernel package ($latest_installed)"
    else
        reboot_needed=true
        echo "REQUIRED: newest installed kernel is $latest_installed, but running kernel is $running_kernel"
    fi
else
    echo "Could not determine newest installed kernel package (no dpkg/rpm found)."
fi
echo ""

echo "=== Stale libraries held open by running processes ==="
if command -v needrestart >/dev/null 2>&1; then
    found_indicator=true
    echo "needrestart -b output:"
    needrestart -b 2>/dev/null | sed 's/^/  /'
else
    echo "needrestart not installed - skipping (apt/dnf install needrestart to enable this check)"
fi
echo ""

if ! $found_indicator; then
    echo "No supported reboot indicator was available on this system."
    exit 2
fi

if $reboot_needed; then
    echo "RESULT: reboot recommended."
    exit 1
else
    echo "RESULT: no reboot indicators found."
    exit 0
fi
