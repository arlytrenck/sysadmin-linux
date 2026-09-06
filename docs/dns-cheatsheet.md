# DNS Cheatsheet

Querying, debugging, and reasoning about name resolution on Linux. Covers
`dig`/`resolvectl`, record types, the resolver stack (`/etc/resolv.conf`,
`systemd-resolved`, `nsswitch`), split-horizon, and the checks that actually
tell you *why* a name won't resolve.

## Query a name

```bash
dig example.com                      # full answer + authority + timing
dig +short example.com              # just the answer data
dig +short example.com A            # explicit type (A, AAAA, MX, TXT, NS, SOA, CNAME, PTR, SRV, CAA)
dig -x 10.0.0.5                     # reverse (PTR) lookup
dig @1.1.1.1 example.com            # ask a specific server, bypass the system resolver
dig @ns1.example.com example.com +norecurse   # ask an authoritative server directly
dig +trace example.com             # walk the delegation from the root down
```

`dig` ignores `nsswitch`/`/etc/hosts` and talks straight to a DNS server. To
test what an *application* will actually get, use `getent` (see below).

## What the system resolver returns

```bash
getent hosts example.com           # goes through nsswitch: files, dns, mdns, ...
getent ahosts example.com          # all address families, with sockaddr detail
resolvectl query example.com       # systemd-resolved's view (per-link, caching)
resolvectl status                  # per-interface DNS servers, search domains, DNSSEC
resolvectl statistics              # cache hits/misses
resolvectl flush-caches            # drop the resolved cache
```

If `dig @server` works but `getent` / the app doesn't, the problem is in the
resolver config, not DNS itself.

## The resolver stack, in order

1. **`/etc/nsswitch.conf`** — the `hosts:` line decides source order, e.g.
   `hosts: files resolve [!UNAVAIL=return] dns`. `files` = `/etc/hosts`.
2. **`/etc/hosts`** — static overrides. Always wins if `files` is first.
3. **`/etc/resolv.conf`** — `nameserver`, `search`, `options`. On a
   systemd-resolved system this is usually a symlink to
   `/run/systemd/resolve/stub-resolv.conf` pointing at `127.0.0.53`.
4. **`systemd-resolved`** (if used) — actual upstreams set per-link by
   NetworkManager / `networkd` / DHCP, seen via `resolvectl status`.

```bash
ls -l /etc/resolv.conf             # symlink target tells you who owns it
cat /etc/nsswitch.conf | grep hosts
resolvectl status | grep -A2 'Link.*(' # real upstreams per interface
```

## Record types you touch most

| Type | Holds | Note |
|------|-------|------|
| `A` / `AAAA` | IPv4 / IPv6 address | |
| `CNAME` | alias to another name | can't coexist with other records at the same name |
| `MX` | mail server + priority | lower priority number wins |
| `TXT` | free text | SPF, DKIM, ACME `_acme-challenge`, domain verification |
| `NS` | delegation to nameservers | at the zone cut |
| `PTR` | reverse (IP → name) | in `in-addr.arpa` / `ip6.arpa` |
| `SRV` | service host + port | `_service._proto.name` |
| `CAA` | which CAs may issue certs | check before debugging ACME failures |
| `SOA` | zone serial + timers | serial must increase on every change |

## TTL and propagation

```bash
dig example.com | grep -A1 'ANSWER SECTION'   # the number before IN A is seconds-to-live
dig +nocmd +noall +answer example.com         # compact
```

- A record change is invisible to a resolver that still has the old answer
  cached — wait out the **old** TTL, not the new one.
- Lower the TTL (e.g. to 300s) *a day before* a planned cutover, then raise
  it again after.
- Check an authoritative server directly (`dig @ns1... +norecurse`) to see
  the truth without cache in the way.

## Split-horizon / hairpin (LAN can't reach its own public IP)

Symptom: `service.example.com` resolves to a public IP, works from outside,
fails from inside the LAN because the router won't NAT-hairpin back to its
own WAN address.

```bash
# from inside the LAN:
dig +short service.example.com                 # returns the public IP
curl -I https://service.example.com            # hangs / connection refused
dig +short @10.0.0.1 service.example.com        # what the LAN resolver says
```

Fix: run a LAN resolver (dnsmasq, AdGuard Home, Pi-hole, Unbound, BIND views)
that answers the internal name with the internal IP, and point DHCP at it.
Verify after:

```bash
dig +short @<lan-resolver> service.example.com  # should be the 10.x/192.168.x address
```

## DNSSEC

```bash
dig +dnssec example.com | grep -E 'RRSIG|ad;'   # 'ad' flag = validated
delv example.com                                # explicit validation chain (bind-dnsutils)
resolvectl query --validate=yes example.com
```

A broken DNSSEC chain returns `SERVFAIL` from a validating resolver but works
from a non-validating one — a useful discriminator.

## Debugging checklist

```bash
dig +short example.com                 # 1. does DNS resolve it at all?
dig +short @1.1.1.1 example.com         # 2. does a public resolver resolve it? (isolates local resolver)
getent hosts example.com               # 3. does the system resolver path agree with dig?
cat /etc/hosts                         # 4. a stale static entry shadowing it?
resolvectl status                      # 5. right upstreams? DNSSEC breaking it?
dig +trace example.com                 # 6. delegation / authoritative problem?
dig example.com SOA +short             # 7. serial increased since the change?
tcpdump -ni any port 53                # 8. is the query even leaving the box, and to where?
```

## Common gotchas

- `search` domains in `resolv.conf` append silently — `dig host` might match
  `host.internal` and mislead you. Test with a trailing dot: `dig host.`
- `systemd-resolved` caches `NXDOMAIN` too — `resolvectl flush-caches` after
  a record is *added*.
- A `CNAME` at the zone apex is invalid; providers that "support" it fake it.
- `nscd` (if installed) is a second cache layer — `nscd -i hosts` to invalidate.
- Containers have their own `/etc/resolv.conf` injected by the runtime; debug
  DNS *inside* the container, not just on the host.
