#!/usr/bin/env bash
#
# network-diagnostics.sh — run a standard sweep of network diagnostics:
# interfaces, routing, listening sockets, DNS resolution, and reachability
# to a set of hosts. Useful as a first pass when "the network is broken."
#
# Usage:
#   ./network-diagnostics.sh [-t host1,host2,...] [-p 80,443]
#
# Options:
#   -t   Comma-separated list of hosts to test reachability against
#        (default: 1.1.1.1,8.8.8.8)
#   -p   Comma-separated list of TCP ports to test against each host
#        (default: 443)
#   -h   Show this help

set -euo pipefail

TARGETS="1.1.1.1,8.8.8.8"
PORTS="443"

usage() {
  grep '^#' "$0" | sed -n '2,10p' | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while getopts ":t:p:h" opt; do
  case "$opt" in
    t) TARGETS="$OPTARG" ;;
    p) PORTS="$OPTARG" ;;
    h) usage 0 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage 1 ;;
    :) echo "Option -$OPTARG requires an argument" >&2; usage 1 ;;
  esac
done

echo "=== Interfaces ==="
ip -brief addr show 2>/dev/null || ifconfig -a

echo
echo "=== Routing table ==="
ip route show 2>/dev/null || route -n

echo
echo "=== Default gateway reachability ==="
GATEWAY="$(ip route show default 2>/dev/null | awk '/default/ {print $3; exit}')"
if [[ -n "$GATEWAY" ]]; then
  if ping -c 2 -W 2 "$GATEWAY" &>/dev/null; then
    echo "OK: default gateway $GATEWAY is reachable"
  else
    echo "WARNING: default gateway $GATEWAY did not respond to ping"
  fi
else
  echo "WARNING: no default route found"
fi

echo
echo "=== Listening sockets ==="
ss -tulpn 2>/dev/null || netstat -tulpn

echo
echo "=== DNS resolution ==="
if command -v dig &>/dev/null; then
  dig +short example.com || echo "WARNING: DNS lookup for example.com failed"
elif command -v getent &>/dev/null; then
  getent hosts example.com || echo "WARNING: DNS lookup for example.com failed"
fi
echo "Resolver config:"
cat /etc/resolv.conf 2>/dev/null | grep -v '^#' || echo "  (no /etc/resolv.conf found)"

echo
echo "=== Host + port reachability ==="
IFS=',' read -ra HOST_LIST <<< "$TARGETS"
IFS=',' read -ra PORT_LIST <<< "$PORTS"
for host in "${HOST_LIST[@]}"; do
  for port in "${PORT_LIST[@]}"; do
    if timeout 3 bash -c "cat < /dev/null > /dev/tcp/$host/$port" 2>/dev/null; then
      echo "OK:      $host:$port is reachable"
    else
      echo "PROBLEM: $host:$port is not reachable"
    fi
  done
done

echo
echo "Done."

