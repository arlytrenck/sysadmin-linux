# Mesh VPN & Remote Access

The wrong way to reach your homelab from outside is to forward ports and hang
admin interfaces off a public reverse proxy. The right way is a mesh VPN: your
devices and your servers get stable private IPs and talk directly, and nothing
is exposed to the internet.

## Options

| | what it is | when |
|---|---|---|
| **WireGuard** (raw) | a fast kernel VPN; you manage keys, IPs, and config by hand | few peers, you want zero third-party involvement |
| **Tailscale** | WireGuard + a coordination server that does key exchange, NAT traversal, ACLs, MagicDNS | most homelabs — it just works, free tier is generous |
| **Headscale** | self-hosted re-implementation of Tailscale's control server | you want Tailscale's UX with no SaaS dependency |
| **Netbird / Nebula / ZeroTier** | similar mesh models | alternatives if Tailscale's model doesn't fit |

For a homelab, Tailscale (or Headscale if you're allergic to SaaS) is the
pragmatic default. Snapshot its config with
[tailscale-export.sh](../scripts/tailscale-export.sh).

## Subnet router (reach the whole LAN, not just the VPN nodes)

Run the client on one always-on box and let it route to the rest of the LAN,
so you don't have to install it on every device (printers, IoT, the NAS UI).

```bash
# on the router node
echo 'net.ipv4.ip_forward = 1'            | sudo tee /etc/sysctl.d/99-vpn.conf
echo 'net.ipv6.conf.all.forwarding = 1'  | sudo tee -a /etc/sysctl.d/99-vpn.conf
sudo sysctl --system

sudo tailscale up --advertise-routes=10.0.0.0/24 --accept-dns=true
# then APPROVE the route in the admin console (it won't route until you do)
```

For raw WireGuard, the equivalent is `AllowedIPs = 10.0.0.0/24` on the peer
plus an `iptables`/`nft` `MASQUERADE` (or `POSTROUTING SNAT`) rule and
`net.ipv4.ip_forward`.

## Throughput tuning for a subnet router

A busy subnet router benefits from UDP GRO forwarding on its uplink NIC:

```bash
IFACE=$(ip -o route get 8.8.8.8 | grep -oP 'dev \K\S+')
sudo ethtool -K "$IFACE" rx-udp-gro-forwarding on rx-gro-list off
# persist with a small systemd oneshot unit
```

## Server nodes: stop the key from expiring

By default a Tailscale node's key expires (~180 days) and it drops off the
tailnet — fine for laptops, bad for a server. In the admin console, **disable
key expiry** for each server node. For raw WireGuard this isn't a thing; keys
don't expire.

## DNS

- **MagicDNS / split DNS**: resolve `host.tailnet.ts.net` names, and push your
  internal `*.example.com` resolver to VPN clients so
  `grafana.example.com` works the same on the couch as on the LAN.
- With a subnet router + split DNS you can drop every public A record for
  LAN-only services.

## Access control

Don't leave the tailnet flat. A minimal ACL: laptops and phones can reach the
server subnet; the server can't initiate back to clients; guests (if any) get
nothing.

```jsonc
// Tailscale ACL sketch
{
  "acls": [
    { "action": "accept", "src": ["group:admins"], "dst": ["10.0.0.0/24:*"] }
  ],
  "ssh": [
    { "action": "accept", "src": ["group:admins"], "dst": ["autogroup:self"], "users": ["autogroup:nonroot", "root"] }
  ]
}
```

## SSH over the mesh

Either use normal `sshd` bound to the VPN interface only, or Tailscale SSH
(`tailscale up --ssh`) which authenticates by tailnet identity and is gated by
the `ssh` ACL above — no keys to distribute, and you can require re-auth for
`root`.

## What this replaces

- Port forwards for SSH / RDP / management UIs → **gone**.
- A public reverse-proxy vhost for Grafana/Proxmox/the router → **gone**; put
  them behind the mesh instead.
- A commercial VPN appliance for "get me into the lab" → **gone**.

Public reverse-proxy vhosts still make sense for things you *want* on the open
internet (a blog, a shared photo album) — just not the admin plane.
