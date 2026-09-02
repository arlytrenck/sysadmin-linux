# Config Snapshots

Most homelab config lives in a UI or a service's own state, not in a file you
edit. Snapshotting it to redacted JSON/text on a schedule and committing it
gives you three things: a diff every time something changes, a baseline for
"what did this look like before the outage", and half a disaster-recovery
plan.

## What to snapshot

| area | source | script / method |
|---|---|---|
| firewall rules | `nft`/`ufw`/`iptables` | [firewall-rules-dump.sh](../scripts/firewall-rules-dump.sh) |
| cron & timers | crontabs + `systemctl list-timers` | [cron-audit.sh](../scripts/cron-audit.sh) |
| installed packages | package manager | [package-inventory.sh](../scripts/package-inventory.sh) |
| systemd units | `/etc/systemd/system/*`, `systemctl list-unit-files` | `cp` + `systemctl` |
| DNS zone | provider API (read-only token) | `curl` the API → JSON |
| reverse-proxy routes | Caddy `/config/`, Traefik `/api/rawdata`, `nginx -T` | `curl` / `nginx -T` |
| TLS certs | ACME client data dir | [acme-cert-report.sh](../scripts/acme-cert-report.sh) |
| Grafana | HTTP API | [grafana-dashboard-export.sh](../scripts/grafana-dashboard-export.sh) |
| mesh VPN ACL / DNS / devices | Tailscale API | [tailscale-export.sh](../scripts/tailscale-export.sh) |
| container stack state | `docker compose config`, `inspect` | [compose-drift.sh](../scripts/compose-drift.sh) |
| the hypervisor / NAS | its own API or config dir | `curl` / `cp`, redacted |

## Redact reliably

Every snapshot must go through a redactor before it lands, or a token ends up
in git. A conservative, generic pass:

- Replace the value of any JSON/YAML key whose name matches
  `/(?i)(key|secret|token|password|auth|credential)/` with `<REDACTED>`.
- Blank anything matching a known token prefix (`tskey-`, `glsa_`, `xoxb-`,
  AWS `AKIA...`, a 40-hex string, etc.).
- Drop `-----BEGIN ... PRIVATE KEY-----` blocks entirely.

Over-redact. A snapshot rarely needs the real secret to be useful for
diffing, and the real values belong in a password manager anyway.

```bash
# sed pass for JSON-ish text
sed -E '
  s/("[A-Za-z0-9_]*([Kk]ey|[Ss]ecret|[Tt]oken|[Aa]uth|[Pp]assword)[A-Za-z0-9_]*"[[:space:]]*:[[:space:]]*)"[^"]*"/\1"<REDACTED>"/g
  s/(tskey-[a-z0-9-]{6})[a-z0-9-]+/\1<REDACTED>/g
'
```

For structured JSON, a `jq` `walk` that masks by key name is more robust — see
[grafana-dashboard-export.sh](../scripts/grafana-dashboard-export.sh).

## Store it

- One directory per area under a config repo, or a top-level `snapshots/`.
- Write a `SHA256SUMS` and a short `README.txt` (what, when, how to refresh)
  alongside each set.
- Keep the repo secret-clean:
  [config-as-code-repo-hygiene.md](config-as-code-repo-hygiene.md).

## Schedule it

Run the exports from cron, then let
[nightly-git-mirror.sh](../scripts/nightly-git-mirror.sh) commit and push the
drift. Gate the noisier ones (full package inventory, host-config tarball) to
weekly so you don't get a commit every night for nothing.

```cron
# daily: cheap, high-signal
15 3 * * *  /opt/snapshots/run-daily.sh   >> /var/log/snapshots.log 2>&1
# weekly: the heavier captures
30 3 * * 0  /opt/snapshots/run-weekly.sh  >> /var/log/snapshots.log 2>&1
```

## Use the diffs

`git log -p snapshots/firewall.txt` is a change history for your firewall that
you didn't have to maintain. When something breaks "and nobody changed
anything", the last few commits usually say otherwise. For a planned change,
snapshot before and after and attach the diff to the change record
([change-management-checklist.md](change-management-checklist.md)).
