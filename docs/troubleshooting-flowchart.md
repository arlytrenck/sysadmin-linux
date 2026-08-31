# Troubleshooting Flowchart

A quick triage flow for "something's wrong with this host" — where to
look first, in what order, before diving deep. Complements
[troubleshooting-guide.md](troubleshooting-guide.md), which is a
reference for specific symptoms; this document is about *where to
start* when you don't yet know which category the problem is in.

## Start here: what's the symptom?

```
Host/service unresponsive or slow
  │
  ├─ Can you SSH in at all?
  │    │
  │    ├─ No  → suspect network/firewall/host-down. Go to NETWORK.
  │    │
  │    └─ Yes → continue below
  │
  ├─ Is load average very high relative to CPU count?
  │    └─ Yes → go to CPU
  │
  ├─ Is available memory near zero / is swap thrashing?
  │    └─ Yes → go to MEMORY
  │
  ├─ Is disk usage near 100% on any mounted filesystem?
  │    └─ Yes → go to DISK
  │
  └─ None of the above obviously true?
       → check recent changes first (see "Recent changes" below),
         then go to LOGS for anything that started around when the
         symptom did
```

## CPU

1. `top`/`htop` sorted by CPU — one runaway process, or broad load
   across many? A single process usually means a bug or a stuck
   request; broad load usually means real traffic or a scheduling
   problem.
2. [process-watchdog.sh](../scripts/process-watchdog.sh) flags
   processes over a CPU threshold and zombies in one pass.
3. If it's one process: is it making progress (check `strace -p PID`
   briefly) or genuinely stuck? A stuck process eating CPU (spinning)
   is a different problem than one doing real, if excessive, work.
4. Check for a recent deploy or cron job that might explain a new
   CPU-heavy process — see "Recent changes" below.

## Memory

1. `free -h` — how much is actually free vs. cached (cache is
   reclaimable, don't panic over low "free" alone; look at "available").
2. Check `dmesg`/`journalctl -k` for OOM-killer activity — if the
   kernel already killed something, that explains a lot.
3. [process-watchdog.sh](../scripts/process-watchdog.sh) flags
   processes over a memory threshold.
4. Is swap enabled and thrashing (`vmstat 1`, watch `si`/`so`
   columns)? Heavy swap I/O is often the actual cause of "everything is
   slow" even when no single process looks obviously wrong.

## Disk

1. [disk-usage-report.sh](../scripts/disk-usage-report.sh) for a
   fast top-consumers view.
2. Out of *space* vs. out of *inodes* are different problems —
   `df -h` and `df -i` both, since a full inode table with plenty of
   free space is an easy miss.
3. A filesystem showing full but `du` not accounting for the space
   usually means a deleted-but-still-open file — `lsof +L1` finds
   processes holding those.
4. [log-cleanup.sh](../scripts/log-cleanup.sh) or manual log rotation
   if logs are the culprit, which they often are.

## Network

1. Can you reach the host at all (ping, or from another host on the
   same network if ICMP is filtered)?
2. [network-diagnostics.sh](../scripts/network-diagnostics.sh) covers
   interfaces, routing, and DNS in one pass.
3. [firewall-rules-dump.sh](../scripts/firewall-rules-dump.sh) if
   something that used to be reachable suddenly isn't — a rule change
   is a common, easy-to-miss cause.
4. Check the provider/hypervisor status page if this is a VM or cloud
   instance — sometimes it's not your host at all.

## Logs

1. [log-anomaly-scan.sh](../scripts/log-anomaly-scan.sh) — is there
   an actual spike in error-rate, or does it just feel like there is?
2. `journalctl --since "1 hour ago" -p err` (or narrower/wider as
   needed) once you have an approximate time window from the above.
3. Correlate timestamps across application logs, `journalctl`, and
   `dmesg` — the full story is often split across more than one source.

## Recent changes

Ask this early, not last — most incidents trace back to *something
that changed*, and knowing what changed narrows everything above
dramatically:

- What was deployed, patched, or configured recently? Check
  [pending-reboot-check.sh](../scripts/pending-reboot-check.sh) if a
  patch was applied but a reboot never happened.
- Did a cron/timer job run around when the symptom started? See
  [cron-audit.sh](../scripts/cron-audit.sh).
- Was there a traffic or usage change (a launch, a spike, a new
  integration) that's real load rather than a bug?

## When you're stuck

Escalate with what you've *ruled out*, not just the symptom — "CPU and
memory are normal, disk has headroom, no recent deploys, but response
time tripled at 14:30" is far more useful to the next person than
"the server is slow."
