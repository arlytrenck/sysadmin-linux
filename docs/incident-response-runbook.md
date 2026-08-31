# Incident Response Runbook

A general-purpose first-response guide for "something is wrong" on a
Linux server. Follow the phases in order; don't skip straight to fixing
without at least a quick assessment, or you risk destroying evidence or
making things worse.

## 1. Assess

- What alerted you? (monitoring, user report, log spike, manual discovery)
- Is the service actually down, or degraded? Confirm independently
  (`curl`, `systemctl status`, `journalctl -xe`) rather than trusting a
  single dashboard.
- Is this isolated to one host, or fleet-wide?
- Note the time you started — you'll want this for the postmortem.

## 2. Contain

- If this looks like a security incident (unexpected processes, unknown
  SSH sessions, unfamiliar cron jobs, outbound traffic to unknown hosts):
  - Isolate the host from the network if you can afford the downtime
    (better to contain than let it spread)
  - Do **not** reboot or wipe the box yet — you may need the running state
    for forensics
  - Rotate credentials that may have been exposed
- If this looks like a capacity/performance issue:
  - Check `disk-usage-report.sh`, `top`/`htop`, `dmesg` for OOM kills
  - Check for a runaway process or log flooding disk usage

## 3. Diagnose

Useful starting points, roughly in order:

```bash
systemctl --failed
journalctl -p err -b
dmesg -T | tail -100
df -hP
free -h
uptime
ss -tulpn
```

Check application-specific logs next. Cross-reference the timestamp of the
first symptom against recent deploys, config changes, or cron jobs
(`grep` your change log / deployment history for that window).

## 4. Mitigate

- Prefer the smallest change that restores service (restart a unit, roll
  back a deploy, free disk space) over a large fix under pressure
- Use `service-health-check.sh --restart` for a quick, logged restart of
  known units
- If you have to make an emergency change, note exactly what you changed —
  you'll need it for step 6

## 5. Verify

- Confirm the service is actually healthy from a client's perspective, not
  just that the process is running
- Watch for a few minutes to make sure the issue doesn't immediately
  recur
- Re-check dependent services

## 6. Document

Within 24 hours, write a short postmortem covering:

- Timeline (detection → containment → resolution)
- Root cause (or best current understanding)
- Impact (what was affected, for how long)
- Follow-up actions, each with an owner

Keep this factual and blameless — the goal is a system that fails this way
less often, not a scapegoat.

