# Documentation Index

Everything in this directory is written to be used while something is
happening, not read cover to cover. Grouped below by the question that
sends you looking for it. The [repository README](../README.md) has the
same files listed as a plain tree if you already know the name.

Nothing here is environment-specific: paths, thresholds, and package
managers are examples, and you should expect to adapt them.

## Setting up a host

- [new-server-bootstrap-checklist.md](new-server-bootstrap-checklist.md)
  — day-0 procedure for a fresh box, in order.
- [server-hardening-checklist.md](server-hardening-checklist.md) — what
  to change before it carries traffic.
- [ssh-hardening-reference.md](ssh-hardening-reference.md) — an
  `sshd_config` baseline with the reasoning for each setting.
- [container-host-tuning.md](container-host-tuning.md) — kernel and
  daemon settings that matter once the box runs containers.

## Day-to-day command references

- [linux-cheatsheet.md](linux-cheatsheet.md) — processes, files,
  permissions, journald, disks.
- [systemd-cheatsheet.md](systemd-cheatsheet.md) — units, drop-ins,
  timers, resource control, sandboxing.
- [cron-and-timers-cheatsheet.md](cron-and-timers-cheatsheet.md) —
  crontab syntax and its traps, systemd timers, recovering a lost
  crontab.
- [text-processing-cheatsheet.md](text-processing-cheatsheet.md) —
  grep, sed, awk, jq, and the one-liners worth memorising.
- [git-cheatsheet.md](git-cheatsheet.md) — reflog and bisect recovery,
  history search, config repos.
- [database-cli-cheatsheet.md](database-cli-cheatsheet.md) — psql,
  mysql, redis-cli, sqlite3.
- [glossary.md](glossary.md) — terms used across these documents.

## Networking, DNS, and access

- [networking-cheatsheet.md](networking-cheatsheet.md) — ip, ss, dig,
  tcpdump, nftables, plus a subnet quick-reference.
- [dns-cheatsheet.md](dns-cheatsheet.md) — record types, the resolver
  stack, split-horizon.
- [firewall-cheatsheet.md](firewall-cheatsheet.md) — nftables, ufw,
  firewalld, and the Docker rule-bypass problem.
- [ssh-cheatsheet.md](ssh-cheatsheet.md) — keys, agent, config,
  tunnels, transfers, debugging.
- [mesh-vpn-remote-access.md](mesh-vpn-remote-access.md) — remote
  access without exposing a port.
- [reverse-proxy-and-tls.md](reverse-proxy-and-tls.md) and
  [reverse-proxy-sso-runbook.md](reverse-proxy-sso-runbook.md) —
  terminating TLS and putting auth in front of an app.
- [tls-cheatsheet.md](tls-cheatsheet.md) — inspecting certificates,
  `openssl s_client`, how ACME works.

## Storage and backup

- [lvm-disk-partitioning-cheatsheet.md](lvm-disk-partitioning-cheatsheet.md)
  — parted, mkfs, LVM, mounting, swap.
- [zfs-cheatsheet.md](zfs-cheatsheet.md) — pools, datasets, snapshots,
  scrub, send/recv, ARC.
- [backup-3-2-1-runbook.md](backup-3-2-1-runbook.md) — designing
  backups that actually restore.
- [backup-dr-testing-runbook.md](backup-dr-testing-runbook.md) and
  [backup-restore-drill.md](backup-restore-drill.md) — exercising them
  on a schedule, because an untested backup is a hypothesis.
- [database-backup-restore-guide.md](database-backup-restore-guide.md)
  — dumps, PITR, and restoring into a running service.
- [rsync-cheatsheet.md](rsync-cheatsheet.md) — the flags that matter,
  `--delete` safety, the CIFS mtime trap, `--link-dest`.
- [nas-hardening-audit-runbook.md](nas-hardening-audit-runbook.md)

## Containers

- [docker-compose-hardening-cheatsheet.md](docker-compose-hardening-cheatsheet.md)
  — the hardened YAML patterns, copy-pasteable.
- [container-security-guide.md](container-security-guide.md) — the
  reasoning behind those patterns.
- [config-as-code-repo-hygiene.md](config-as-code-repo-hygiene.md) —
  keeping compose files in git without leaking secrets.

## Monitoring, logging, and capacity

- [monitoring-alerting-guide.md](monitoring-alerting-guide.md) — what
  to alert on, and what to leave as a dashboard.
- [log-management-reference.md](log-management-reference.md) —
  journald, rotation, retention, shipping.
- [capacity-planning-guide.md](capacity-planning-guide.md) — noticing
  you are going to run out before you do.
- [config-snapshots.md](config-snapshots.md) — capturing config so
  drift is visible.
- [single-node-homelab-reliability.md](single-node-homelab-reliability.md)
  — how far you can get without a cluster.

## When something is broken

Start here:

- [troubleshooting-flowchart.md](troubleshooting-flowchart.md) — triage
  order when you do not yet know what kind of problem it is.
- [troubleshooting-guide.md](troubleshooting-guide.md) — reference for
  specific symptoms once you do.

Then the runbook that matches:

- [incident-response-runbook.md](incident-response-runbook.md)
- [disk-full-emergency-runbook.md](disk-full-emergency-runbook.md) —
  filesystem at 100%: stop the bleeding, then prevent it.
- [secret-rotation-runbook.md](secret-rotation-runbook.md) — rotating a
  credential with overlap and a rollback path.
- [privileged-access-and-break-glass-runbook.md](privileged-access-and-break-glass-runbook.md)
  — sudo and root access, break-glass accounts, periodic review.
- [hypervisor-major-upgrade-runbook.md](hypervisor-major-upgrade-runbook.md)

## Process and templates

- [patch-management-guide.md](patch-management-guide.md) — patch rings,
  unattended upgrades, and the container image stream people forget.
- [change-management-checklist.md](change-management-checklist.md)
- [incident-postmortem-template.md](incident-postmortem-template.md)
- [disaster-recovery-plan-template.md](disaster-recovery-plan-template.md)
- [resource-library.md](resource-library.md) — upstream documentation
  for every tool referenced here.
