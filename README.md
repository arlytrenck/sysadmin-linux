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
│   └── user-activity-report.sh   # logins, failed logins, recent sudo usage
└── docs/
    ├── server-hardening-checklist.md
    ├── incident-response-runbook.md
    ├── troubleshooting-guide.md
    ├── ssh-hardening-reference.md
    ├── systemd-cheatsheet.md
    └── networking-cheatsheet.md
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

## License

MIT — use at your own risk, no warranty. See individual scripts for details.
