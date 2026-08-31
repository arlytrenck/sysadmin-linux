# sysadmin-linux

A collection of Linux server administration scripts, runbooks, and reference
documentation, gathered from day-to-day homelab and small-fleet operations.

A companion repo, [sysadmin-windows](https://github.com/arlytrenck/sysadmin-windows),
covers the same ground for Windows Server environments.

## Layout

```
sysadmin-linux/
├── scripts/
│   ├── backup-rotate.sh          # tar-based backups with retention
│   ├── user-mgmt.sh              # create/lock/remove users, SSH key setup
│   ├── disk-usage-report.sh      # top disk consumers + threshold alerting
│   ├── log-cleanup.sh            # prune/compress old logs
│   ├── service-health-check.sh   # check & optionally restart systemd units
│   ├── update-and-patch.sh       # apt/dnf update wrapper with logging
│   ├── network-diagnostics.sh    # interfaces, routing, DNS, reachability
│   ├── security-audit.sh         # SUID/SGID, world-writable, sudoers, etc.
│   ├── package-inventory.sh      # snapshot installed packages, diff baselines
│   ├── user-activity-report.sh   # logins, failed logins, recent sudo usage
│   ├── cert-expiry-check.sh      # TLS cert expiry, live host or local file
│   ├── cron-audit.sh             # enumerate cron/timers across the system
│   ├── firewall-rules-dump.sh    # snapshot nftables/ufw/iptables rules
│   ├── ssh-key-audit.sh          # audit authorized_keys for weak/shared keys
│   ├── raid-smart-health-check.sh # mdadm + SMART disk health check
│   ├── process-watchdog.sh       # flag runaway CPU/mem and zombie processes
│   ├── pending-reboot-check.sh   # detect whether a reboot is waiting to apply
│   ├── log-anomaly-scan.sh       # flag error-rate spikes vs. a trailing baseline
│   └── docker-container-audit.sh # flag root/privileged/unbounded/restart-looping containers
└── docs/
    ├── server-hardening-checklist.md
    ├── incident-response-runbook.md
    ├── troubleshooting-guide.md
    ├── ssh-hardening-reference.md
    ├── systemd-cheatsheet.md
    ├── networking-cheatsheet.md
    ├── backup-dr-testing-runbook.md
    ├── monitoring-alerting-guide.md
    ├── database-backup-restore-guide.md
    ├── capacity-planning-guide.md
    ├── container-security-guide.md
    └── log-management-reference.md
```

## Usage

Each script is self-contained, POSIX-ish bash, and documents its own options
via `-h`/`--help`. Review the source before running anything against a
production host — these are starting points, not turnkey solutions, and you
should adapt paths, thresholds, and package managers to your environment.

```bash
chmod +x scripts/*.sh
./scripts/disk-usage-report.sh --help
```

## Requirements

- Bash 4+
- Standard GNU coreutils
- `systemctl`/`journalctl` for `service-health-check.sh`, `user-activity-report.sh`
- `apt` or `dnf`/`yum`/`rpm` for `update-and-patch.sh` and `package-inventory.sh` (auto-detected)
- `ip`/`ss`/`dig` (iproute2 + bind-utils/dnsutils) for `network-diagnostics.sh`
- `openssl` for `cert-expiry-check.sh`
- `nft`, `ufw`, or `iptables` (whichever is in use) for `firewall-rules-dump.sh`
- `ssh-keygen` (openssh-client) for `ssh-key-audit.sh`
- `mdadm` and/or `smartmontools` (smartctl) for `raid-smart-health-check.sh`
- `journalctl` (systemd) recommended for `log-anomaly-scan.sh` and
  `pending-reboot-check.sh`; both fall back to other sources if absent
- `docker` for `docker-container-audit.sh` (skips cleanly if not installed)

## Contributing

Bug reports, script/doc suggestions, and pull requests are welcome — see
[CONTRIBUTING.md](CONTRIBUTING.md) for the process and style guidelines.
Pushes and PRs touching `scripts/**.sh` run through
[ShellCheck](.github/workflows/shellcheck.yml) in CI.

## License

MIT — see [LICENSE](LICENSE). Use at your own risk, no warranty.
