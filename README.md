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
│   ├── docker-container-audit.sh # flag root/privileged/unbounded/restart-looping containers
│   ├── compose-validate.sh      # docker compose config on every stack under a dir
│   ├── compose-env-example.sh   # generate/verify .env.example from compose ${VAR} refs
│   ├── grafana-dashboard-export.sh # Grafana dashboards/datasources/alerting -> redacted JSON
│   ├── tailscale-export.sh      # Tailscale node + tailnet config -> redacted JSON
│   ├── age-backup.sh            # tar+gzip -> age-encrypt -> rotate -> checksum (off-host copy)
│   ├── stack-db-dump.sh         # dump every DB container across a set of compose stacks
│   ├── compose-drift.sh         # running containers vs. what compose declares; flag ad-hoc
│   ├── healthcheck-audit.sh     # containers with no HEALTHCHECK / unhealthy / restart-looping
│   ├── bind-mount-audit.sh      # flag risky host bind mounts (writable /etc, docker.sock, ...)
│   ├── compose-image-updates.sh # registry check for newer digests than pinned/running images
│   ├── acme-cert-report.sh      # certs managed by Caddy/certbot/acme.sh/Traefik + expiry
│   ├── nightly-git-mirror.sh    # add -A / commit-if-drift / push, for cron; non-fatal
│   ├── backup-verify.sh         # assert backups exist, are recent, pass an integrity check
│   ├── system-snapshot.sh       # redacted tarball of an /etc subset + system inventory
│   ├── listening-ports-audit.sh # every listening TCP/UDP socket, flag vs. an allowlist
│   ├── swap-memory-pressure-check.sh # mem/swap thresholds, PSI stalls, recent OOM kills
│   └── time-sync-check.sh       # chrony/timesyncd/ntpd sync status + offset threshold
└── docs/
    # cheatsheets & references
    ├── linux-cheatsheet.md              # processes, files, permissions, journald, disks
    ├── networking-cheatsheet.md         # ip/ss/dig/tcpdump/nftables + subnet quick-ref
    ├── systemd-cheatsheet.md            # units, drop-ins, timers, resource control, sandboxing
    ├── ssh-cheatsheet.md                # keys, agent, config, tunnels, transfer, debugging
    ├── ssh-hardening-reference.md       # sshd_config baseline, with reasoning
    ├── tls-cheatsheet.md                # inspecting certs, openssl s_client, ACME concepts
    ├── git-cheatsheet.md                # reflog/bisect recovery, history search, config repos
    ├── zfs-cheatsheet.md                # pools, datasets, snapshots, scrub, send/recv, ARC
    ├── lvm-disk-partitioning-cheatsheet.md  # parted/fdisk, mkfs, LVM, mounting, swap
    ├── text-processing-cheatsheet.md    # grep/sed/awk/jq, sort/uniq/cut, one-liners
    ├── database-cli-cheatsheet.md       # psql/mysql/redis-cli/sqlite3 day-to-day commands
    ├── docker-compose-hardening-cheatsheet.md  # hardened compose YAML patterns
    ├── container-security-guide.md      # the principles behind the compose patterns
    ├── log-management-reference.md
    ├── monitoring-alerting-guide.md
    ├── capacity-planning-guide.md
    ├── database-backup-restore-guide.md
    # checklists
    ├── new-server-bootstrap-checklist.md  # day-0 procedure for a fresh box
    ├── server-hardening-checklist.md
    ├── change-management-checklist.md
    # runbooks
    ├── incident-response-runbook.md
    ├── backup-3-2-1-runbook.md          # a backup design that actually restores
    ├── backup-dr-testing-runbook.md     # exercising those backups on a schedule
    ├── hypervisor-major-upgrade-runbook.md
    ├── nas-hardening-audit-runbook.md
    ├── reverse-proxy-sso-runbook.md
    # troubleshooting & templates
    ├── troubleshooting-guide.md
    ├── troubleshooting-flowchart.md
    ├── container-host-tuning.md
    ├── config-as-code-repo-hygiene.md
    ├── single-node-homelab-reliability.md
    ├── backup-restore-drill.md
    ├── reverse-proxy-and-tls.md
    ├── mesh-vpn-remote-access.md
    ├── config-snapshots.md
    ├── incident-postmortem-template.md
    ├── disaster-recovery-plan-template.md
    └── glossary.md
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
- `docker` for `docker-container-audit.sh` and `compose-validate.sh` (both skip cleanly if absent)
- `jq` for `grafana-dashboard-export.sh`; `curl` for it and `tailscale-export.sh --api`
- `tailscale` (CLI) for `tailscale-export.sh`
- `age` for `age-backup.sh` (it refuses to run without it — no plaintext fallback)
- `docker` (v2 compose) + `jq` for `compose-drift.sh` and `stack-db-dump.sh`
- `skopeo`, `crane`, or `docker buildx` for `compose-image-updates.sh`
- `openssl` (already listed) for `acme-cert-report.sh`; `jq` for its Traefik acme.json path
- `git` with working push auth for `nightly-git-mirror.sh`
- `tar`, `gzip`, `sha256sum` for `backup-verify.sh` and `system-snapshot.sh`;
  `zstd` and `age` are used by `backup-verify.sh` only if the archives need them

## Contributing

Bug reports, script/doc suggestions, and pull requests are welcome — see
[CONTRIBUTING.md](CONTRIBUTING.md) for the process and style guidelines.
Pushes and PRs touching `scripts/**.sh` run through
[ShellCheck](.github/workflows/shellcheck.yml) in CI.

## License

MIT — see [LICENSE](LICENSE). Use at your own risk, no warranty.
