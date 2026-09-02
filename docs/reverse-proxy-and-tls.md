# Reverse Proxy & TLS for Self-Hosted Services

One box, many web apps on `127.0.0.1:<port>`, one public IP. A reverse proxy
gives each service a name, terminates TLS, and is the single place to enforce
auth and headers.

## Picking one

| | strength | tradeoff |
|---|---|---|
| **Caddy** | automatic HTTPS with almost no config; readable Caddyfile | fewer knobs for exotic routing |
| **Traefik** | dynamic config from Docker labels; good for churny stacks | steeper learning curve; `acme.json` is a single fragile file |
| **nginx + certbot** | you already know it; total control | you own cert renewal and reload wiring |

For a mostly-static homelab stack, Caddy is the least to go wrong. Whatever
you pick, report on what it's actually managing with
[acme-cert-report.sh](../scripts/acme-cert-report.sh).

## ACME challenge: HTTP-01 vs DNS-01

- **HTTP-01** — the CA hits `http://name/.well-known/acme-challenge/...`.
  Needs port 80 reachable from the internet. Fine for genuinely public names.
- **DNS-01** — you prove control by writing a TXT record. Works for names that
  **never** point at a public IP (LAN-only services), and is the only way to
  get a **wildcard** (`*.example.com`). Needs an API token scoped to *DNS
  edit* for that one zone — nothing more.

For a homelab, DNS-01 with a wildcard is usually the move: one cert covers
every subdomain, and services that only listen on the LAN still get real
certs.

```
# Caddy: DNS-01 via a provider plugin, wildcard
*.example.com {
    tls {
        dns cloudflare {env.CF_API_TOKEN}
    }
    @app host app.example.com
    handle @app { reverse_proxy 127.0.0.1:3001 }
    # ...more @host blocks...
}
```

Keep the token in the environment / a systemd drop-in, not the Caddyfile.

## LAN-only services

Give internal apps a name that resolves to the LAN IP and refuse non-LAN
clients at the proxy:

```
grafana.example.com {
    @external not remote_ip 10.0.0.0/24 192.168.0.0/16
    respond @external 403
    reverse_proxy 127.0.0.1:3000
}
```

## Split-horizon DNS (so internal traffic stays internal)

If `app.example.com` has a public A record, LAN clients will hairpin out to
your WAN IP and back. Avoid it by resolving `*.example.com` to the proxy's LAN
IP **on the LAN** — a local DNS override on your resolver (Pi-hole, Unbound,
your router, or the reverse proxy's own DNS). External DNS stays as-is (or
absent, for LAN-only names).

## Single sign-on in front of everything

Put an auth portal (Authelia, Authentik, `oauth2-proxy`) between the proxy and
apps that have weak or no auth:

```
# Caddy: gate a route behind forward_auth
handle @app {
    forward_auth 127.0.0.1:9091 {
        uri /api/verify?rd=https://auth.example.com
        copy_headers Remote-User Remote-Groups Remote-Email
    }
    reverse_proxy 127.0.0.1:3001
}
```

Apps that do their own auth-proxy trust (e.g. Grafana `GF_AUTH_PROXY_*`) read
the `Remote-*` headers and skip their own login.

## Headers worth setting globally

```
header {
    Strict-Transport-Security "max-age=31536000; includeSubDomains"
    X-Content-Type-Options "nosniff"
    X-Frame-Options "SAMEORIGIN"
    Referrer-Policy "strict-origin-when-cross-origin"
    -Server
}
```

Add a `Content-Security-Policy` per app once you know what it loads — start in
report-only mode.

## Renewal safety net

Autorenewal fails silently more often than you'd think (expired API token,
rate limit, a challenge that stopped resolving). Run
[acme-cert-report.sh](../scripts/acme-cert-report.sh) daily and
[cert-expiry-check.sh](../scripts/cert-expiry-check.sh) against the live
vhosts, and alert if anything is inside 14 days.
