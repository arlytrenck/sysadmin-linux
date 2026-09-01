# TLS Cheatsheet

## Inspect a cert on a live service
```bash
openssl s_client -connect host:443 -servername host </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates -ext subjectAltName
# expiry only, machine-readable:
openssl s_client -connect host:443 -servername host </dev/null 2>/dev/null \
  | openssl x509 -noout -enddate
# full chain the server presents:
openssl s_client -connect host:443 -servername host -showcerts </dev/null
```

## Inspect a cert file
```bash
openssl x509 -in cert.pem -noout -text
openssl x509 -in cert.pem -noout -fingerprint -sha256
openssl rsa  -in key.pem  -noout -check          # key valid?
# key and cert must match — these two hashes must be equal:
openssl x509 -in cert.pem -noout -modulus | openssl md5
openssl rsa  -in key.pem  -noout -modulus | openssl md5
```

## CSR / self-signed (lab only)
```bash
openssl req -new -newkey rsa:2048 -nodes -keyout k.pem -out c.csr \
  -subj '/CN=host.example.com' \
  -addext 'subjectAltName=DNS:host.example.com'
openssl req -x509 -newkey rsa:2048 -nodes -keyout k.pem -out c.pem -days 365 \
  -subj '/CN=host.example.com' -addext 'subjectAltName=DNS:host.example.com'
```

## Verify a chain
```bash
openssl verify -CAfile chain.pem cert.pem
# server sending an incomplete chain is the #1 "works in browser, fails in curl"
# cause — fix it on the server, don't add CAs on clients.
```

## ACME / Let's Encrypt concepts
- **HTTP-01**: prove control by serving a token at `http://host/.well-known/acme-challenge/…`.
  Needs port 80 reachable; can't do wildcards.
- **DNS-01**: prove control by publishing a `_acme-challenge` TXT record. Works
  behind NAT/firewall and does wildcards; needs an API token for your DNS
  provider (scope it to *DNS edit for one zone*, nothing more).
- Renew early (30 days out), reload the service after renewal, and **monitor
  expiry independently** — renewal automation fails silently more often than
  you'd like. See [../scripts/cert-expiry-check.sh](../scripts/cert-expiry-check.sh).

## Quick server-config sanity
```bash
nmap --script ssl-enum-ciphers -p 443 host        # protocols + cipher grades
# want: TLS1.2 + TLS1.3 only, no TLS1.0/1.1, HSTS header set, OCSP stapling on.
```
