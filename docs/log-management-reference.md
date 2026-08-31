# Log Management Reference

Practical notes on where Linux logs live, how to keep them from filling a
disk, and how to get useful signal out of them without standing up a full
observability stack. Pairs with
[log-cleanup.sh](../scripts/log-cleanup.sh) (retention/pruning) and
[log-anomaly-scan.sh](../scripts/log-anomaly-scan.sh) (spike detection).

## Where logs live

- **journald** (systemd-based distros): binary, structured logs read via
  `journalctl`. Persists to `/var/log/journal/` if that directory exists
  and `Storage=persistent` is set in `/etc/systemd/journald.conf`;
  otherwise it's volatile and lost on reboot.
- **rsyslog / syslog-ng**: traditional plain-text logs under `/var/log/`
  (`syslog`, `auth.log`, `messages`, etc.), often fed *from* journald via
  `imjournal` on distros that run both.
- **Application-specific logs**: most services that aren't pure systemd
  units still write their own files (`/var/log/nginx/`,
  `/var/log/mysql/`, application log directories) — these need their own
  rotation config, since `logrotate`'s defaults only cover what's listed
  in `/etc/logrotate.d/`.

## journald retention

```bash
# Check current disk usage by the journal
journalctl --disk-usage

# Cap total journal size
journalctl --vacuum-size=500M

# Cap by age
journalctl --vacuum-time=30d

# Persist across reboots (if not already persistent)
sudo mkdir -p /var/log/journal
sudo systemd-tmpfiles --create --prefix /var/log/journal
sudo systemctl restart systemd-journald
```

Set permanent limits in `/etc/systemd/journald.conf` (`SystemMaxUse=`,
`SystemMaxFileSize=`) rather than relying on periodic manual vacuuming —
an unbounded journal on a busy host can fill `/var` unnoticed.

## logrotate for flat files

Most distros ship sensible per-package `/etc/logrotate.d/` configs
already. When adding your own application's logs:

```
/var/log/myapp/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
```

`copytruncate` is the safer default for an application that doesn't
reopen its log file on `SIGHUP` — it avoids needing to signal the
process, at the small cost of a possible few lost log lines at the
rotation instant.

## Retention: how long is long enough?

- **Security/audit-relevant logs** (auth, sudo usage): keep long enough
  to cover your incident-detection window — 90+ days is a common
  baseline, longer if a compliance regime requires it.
- **Debug/application-noise logs**: 7-14 days is often plenty; they're
  usually only useful for troubleshooting something that just happened.
- **Anything feeding capacity planning or trend analysis** (see
  [capacity-planning-guide.md](capacity-planning-guide.md)): keep
  aggregated/summarized data much longer than raw logs — a monthly
  count is cheap to keep for years, the raw lines behind it aren't.

## Getting signal out of logs without a full stack

- **Start with rate, not content.** "Errors per minute is 5x normal" is
  a useful alert with far less setup than parsing every error string —
  this is the approach `log-anomaly-scan.sh` takes.
- **journalctl filters are often enough** for ad hoc investigation
  before reaching for a bigger tool: `journalctl -u myservice -p err`,
  `journalctl --since "1 hour ago" -p warning`, `journalctl -k` for
  kernel messages.
- **Centralize once you have more than a handful of hosts.** At small
  scale, SSH + `journalctl`/`grep` across hosts is fine; past a handful
  of hosts, shipping logs somewhere queryable (see
  [monitoring-alerting-guide.md](monitoring-alerting-guide.md)) starts
  paying for itself in incident response time.
- **Correlate by timestamp across sources during an incident** — the
  application log, `journalctl`, and `dmesg`/kernel log often each hold
  one piece of the story; check all three around the same timestamp
  rather than assuming one has the full picture.
