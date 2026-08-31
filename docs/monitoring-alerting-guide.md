# Monitoring & Alerting Setup Guide

A practical starting point for monitoring a small Linux fleet — from "cron
job plus a webhook" up through a proper metrics stack. Pick the tier that
matches your scale; there's no need to run Prometheus for two servers.

## Tier 0: scripts + cron + a notification webhook

The scripts in this repo (`disk-usage-report.sh`, `service-health-check.sh`,
`security-audit.sh`) already exit non-zero on a problem. Wire that into a
notification with almost no infrastructure:

```bash
# /etc/cron.d/disk-check
*/15 * * * * root /usr/local/bin/disk-usage-report.sh -t 10 \
  || curl -s -X POST -H 'Content-Type: application/json' \
       -d '{"text":"Disk threshold breached on '"$(hostname)"'"}' \
       https://hooks.example.com/your-webhook
```

This scales to a handful of hosts and gets you real alerting today. Its
limits: no history/trending, no dashboard, and alert fatigue if thresholds
aren't tuned per-host.

## Tier 1: a metrics agent + hosted or self-hosted backend

Once you want trends (is disk usage growing linearly or did something
spike?) and a dashboard, add a metrics agent:

- **Prometheus node_exporter** + a self-hosted Prometheus + Grafana — full
  control, more to operate yourself.
- **Netdata** — near-zero-config, good default dashboards, works well for
  a handful of hosts without a central server if you just want per-host
  visibility.
- A hosted option (Datadog, Grafana Cloud, etc.) — less infrastructure to
  run, ongoing cost scales with hosts/metrics.

Minimum useful metric set for a general-purpose server: CPU, memory, disk
usage and I/O, network throughput, and systemd unit failures.

## Tier 2: alerting rules on top of metrics

Once metrics are flowing, define alert rules rather than eyeballing
dashboards:

- Alert on trend, not just threshold, where possible — "disk will fill in
  under 48 hours at current growth rate" catches problems earlier than a
  flat "under 10% free" rule and fires less often on temporary spikes.
- Alert on absence, not just presence — a host that stops reporting
  metrics at all is itself worth an alert (a metrics agent that died is
  indistinguishable from "everything's fine" if you only alert on bad
  values).
- Route alerts by severity: a paging alert for "service is down now"
  should not use the same channel as "disk is at 75%, plan ahead."

## Log aggregation (complements metrics, doesn't replace them)

Metrics tell you *that* something's wrong; logs tell you *why*. Options
roughly by operational weight:

- `journalctl` centrally via systemd-journal-remote, for a handful of
  hosts.
- A lightweight shipper (Vector, Fluent Bit, Promtail) to a log backend
  (Loki, self-hosted ELK, or a hosted log service).

## What to actually alert on (a starting list)

- Disk free space below threshold (`disk-usage-report.sh`)
- A monitored service not running (`service-health-check.sh`)
- Repeated failed SSH logins beyond a threshold (`user-activity-report.sh`
  can be scripted into a periodic check)
- Certificate expiry approaching (`cert-expiry-check.sh`)
- Failed scheduled backups (a non-zero exit from `backup-rotate.sh` in its
  cron entry)
- Host unreachable / not reporting metrics at all

## A note on alert fatigue

More alerts is not more safety once people start ignoring them. Every
alert should be actionable — if an alert fires and the response is always
"yeah, ignore that one," either fix the underlying threshold or remove the
alert. Review your alert rules periodically, not just when adding new
ones.

