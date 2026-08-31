# Networking Cheatsheet

Quick reference for inspecting and troubleshooting Linux networking. Prefer
the `ip`/`ss` tool family (iproute2) over the older `ifconfig`/`netstat`/
`route`, which are deprecated on most modern distros but still shown here
since they're often still installed.

## Interfaces and addresses

```bash
ip addr show                 # all interfaces and their addresses
ip -brief addr show           # condensed view
ip link show                  # interfaces without addresses (link layer)
ip link set eth0 up|down      # bring an interface up or down
```

## Routing

```bash
ip route show                 # routing table
ip route show default         # just the default gateway
ip route get 8.8.8.8          # which route/interface would be used for a destination
```

## Listening sockets and connections

```bash
ss -tulpn                     # listening TCP/UDP sockets with owning process
ss -tanp                      # all TCP connections with state
ss -s                         # summary statistics
lsof -i :443                  # what's using a specific port
```

## DNS

```bash
dig example.com               # full query output
dig +short example.com        # just the answer
dig @1.1.1.1 example.com      # query a specific resolver
resolvectl status             # systemd-resolved status, if in use
cat /etc/resolv.conf          # configured resolvers (may be managed elsewhere)
```

## Reachability

```bash
ping -c 4 host                # ICMP reachability (some networks block ICMP — a
                               # failure here isn't conclusive on its own)
traceroute host               # path to a host, hop by hop
mtr host                      # continuous traceroute + ping statistics (interactive)
curl -v telnet://host:port    # TCP port reachability without needing netcat
nc -zv host port              # same, if netcat is installed
```

## Firewall (nftables / iptables / ufw)

```bash
# nftables (current standard on most distros)
sudo nft list ruleset

# iptables (legacy, or nftables in compat mode)
sudo iptables -L -n -v

# ufw (Ubuntu's friendlier front-end)
sudo ufw status verbose
```

## Bandwidth / traffic

```bash
iftop                         # per-connection bandwidth usage, interactive
nload                         # simple per-interface bandwidth graph
vnstat                        # historical bandwidth usage (needs a running daemon)
ss -i                         # per-socket TCP internals (cwnd, rtt, retransmits)
```

## Packet capture

```bash
sudo tcpdump -i eth0 -n port 443          # capture, filter by port
sudo tcpdump -i eth0 -w capture.pcap      # write to a file for later analysis (e.g. Wireshark)
```

Capture only what you need and for a bounded time — `tcpdump` on a busy
interface generates data fast, and packet captures can contain sensitive
payloads.

