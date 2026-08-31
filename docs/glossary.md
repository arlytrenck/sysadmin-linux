# Glossary

Terms used across this repo's scripts and docs, defined at the level
they're used here — not exhaustive references for each subsystem.

**AVC denial** — an "Access Vector Cache" denial logged by SELinux when
it blocks an action; found via `ausearch` or `journalctl`, relevant if
a service mysteriously can't do something despite correct file
permissions.

**Baseline** — a recorded snapshot of expected state (installed
packages, a checksum, a metric's normal range) that later runs compare
against to detect drift. Used by
[package-inventory.sh](../scripts/package-inventory.sh) and the
anomaly-detection approach in
[log-anomaly-scan.sh](../scripts/log-anomaly-scan.sh).

**Blast radius** — how much is affected if a change goes wrong. Smaller
is safer; see [change-management-checklist.md](change-management-checklist.md).

**CVE** — Common Vulnerabilities and Exposures: a public identifier for
a specific known security vulnerability, referenced when patching or
scanning images (see [container-security-guide.md](container-security-guide.md)).

**Idempotent** — an operation that produces the same end state no
matter how many times it's run. Worth aiming for in scripts that change
system state, since a script that's safe to re-run is much easier to
recover with after a partial failure.

**Inode** — the data structure holding a file's metadata (not its
name). A filesystem can run out of inodes while still having free disk
space, especially with many small files — see
[troubleshooting-flowchart.md](troubleshooting-flowchart.md).

**MAC (Mandatory Access Control)** — an access-control model (SELinux,
AppArmor) enforced by the kernel independent of standard Unix
permissions; can block an otherwise-permitted action.

**Multiplier / threshold (anomaly detection)** — in
[log-anomaly-scan.sh](../scripts/log-anomaly-scan.sh), how much higher
than baseline a rate has to be before it's flagged (e.g. 3x). Set too
low, it's noisy; too high, it misses real spikes.

**OOM killer** — the Linux kernel's Out-Of-Memory killer, which
terminates a process (chosen by a scoring heuristic) when the system is
critically low on memory rather than letting it deadlock entirely.
Check `dmesg`/`journalctl -k` after an unexplained process death.

**Postmortem (blameless)** — a writeup after an incident focused on
system and process gaps rather than individual fault. See
[incident-postmortem-template.md](incident-postmortem-template.md).

**RPO / RTO** — Recovery Point Objective (how much data loss is
tolerable, as a time span) and Recovery Time Objective (how long
recovery is allowed to take). Defined in
[disaster-recovery-plan-template.md](disaster-recovery-plan-template.md).

**Runbook** — a procedure written down in enough detail that someone
other than its author can follow it under pressure, as opposed to a
reference doc meant for browsing.

**Sticky bit** — a permission bit on a directory (mode `1000`) that
restricts file deletion to the file's owner even when the directory is
world-writable — expected on `/tmp`, a red flag on other world-writable
directories. Checked by
[security-audit.sh](../scripts/security-audit.sh).

**SUID / SGID** — permission bits that make a binary run with its
owner's (SUID) or group's (SGID) privileges rather than the invoking
user's — a small, security-relevant set of binaries should have these;
unexpected ones are worth investigating.

**Threshold alerting vs. trend alerting** — alerting on a fixed value
("disk is 90% full") vs. on the rate of change ("disk usage is growing
2x faster than last month"). Trend alerting often gives more lead time;
see [capacity-planning-guide.md](capacity-planning-guide.md).

**Zombie process** — a process that has exited but whose entry remains
in the process table because its parent hasn't reaped its exit status.
Harmless individually in small numbers; many of them usually points to
a parent process bug. Flagged by
[process-watchdog.sh](../scripts/process-watchdog.sh).
