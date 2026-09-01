# Reverse proxy + forward-auth SSO + LAN guards

A pattern for putting many small web apps behind one entry point with TLS,
single sign-on, and a "only from the LAN unless authenticated" posture. Shown
with Caddy + a forward-auth provider (Authelia / Authentik / oauth2-proxy); the
shape is the same for Traefik + its `forwardAuth` middleware or nginx +
`auth_request`.

## The pieces

1. **One reverse proxy** terminates TLS for every `app.example.com`.
2. **DNS-01 certificates** so the proxy can issue certs for internal-only names
   without exposing port 80. Scope the DNS API token to *edit one zone*.
3. **A forward-auth service** the proxy calls before proxying: it returns 200
   (allow, plus identity headers) or 302 (redirect to login).
4. **Per-vhost access rules**: LAN CIDR allowed straight through; everything else
   must authenticate; some paths (health, webhooks, API used by embeds) bypass
   auth explicitly.

## Caddy sketch

```caddy
(tls_dns) {
    tls {
        dns cloudflare {env.DNS_API_TOKEN}      # token from the environment, NOT inline
        resolvers 1.1.1.1
    }
}

(lan_or_auth) {
    @lan   remote_ip 10.0.0.0/24 192.168.0.0/16
    @denied not remote_ip 10.0.0.0/24 192.168.0.0/16
    forward_auth @denied 127.0.0.1:9091 {
        uri /api/verify?rd=https://auth.example.com
        copy_headers Remote-User Remote-Groups Remote-Email
    }
}

app.example.com {
    import tls_dns
    import lan_or_auth
    reverse_proxy 127.0.0.1:8080
}

# a service whose embed/API must skip auth on some paths:
grafana.example.com {
    import tls_dns
    @embed path /d-solo/* /api/* /public/*
    reverse_proxy @embed 127.0.0.1:3000
    import lan_or_auth
    reverse_proxy 127.0.0.1:3000
}
```

## Hardening the responses

Add security headers once (a snippet) and import into each vhost:
```caddy
(sec_headers) {
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
        Referrer-Policy "strict-origin-when-cross-origin"
        -Server
    }
}
```

## Rules of thumb

- Every backend app **binds to `127.0.0.1`** — the proxy is the only way in.
- Keep the whole proxy config in git. It changes often and you will want the
  diff when a vhost breaks.
- The DNS/ACME token is the one real secret here: environment variable or a
  `LoadCredential`/secret file, never committed, and scoped minimally.
- Test the auth path from *outside* the LAN CIDR (curl with a spoofed source is
  hard; use a phone on cellular or a remote box) — it's easy to accidentally
  leave something open because you only ever test from your desk.
