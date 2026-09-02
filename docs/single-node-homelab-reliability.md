# Single-Node Homelab Reliability

Running "everything on one box" is fine — most homelabs are one host with a
stack of containers — as long as you treat that box's failure modes
deliberately. This is the checklist for making one node boring.

## Restart & self-heal

- **`restart: unless-stopped`** on every service. Not `always` (which restarts
  things you stopped on purpose), not `on-failure` (which gives up).
- **`live-restore: true`** in `/etc/docker/daemon.json` so containers keep
  running across a `dockerd` restart or upgrade.
- **Healthchecks on everything.** A container that's up but wedged looks fine
  to `docker ps`. Define `HEALTHCHECK` in the image or `healthcheck:` in
  compose. Audit coverage with
  [healthcheck-audit.sh](../scripts/healthcheck-audit.sh).
- **Autoheal** the unhealthy ones: run `willfarrell/autoheal` (watches for
  `unhealthy` and restarts) or a small cron calling
  `docker ps --filter health=unhealthy -q | xargs -r docker restart`.
- **Ordered startup** for dependent services:
  `depends_on: { db: { condition: service_healthy } }`.

## Resource limits (so one service can't take the host down)

With many containers, committed limits usually exceed RAM — that's expected,
most never peak together. But **every** service needs a ceiling so a leak is
OOM-killed instead of the host:

```yaml
deploy:
  resources:
    limits:
      memory: 512M
    # pids and cpus too, for anything that can fork-bomb or spin
```

Set `vm.overcommit_memory = 1` to go with it — see
[container-host-tuning.md](container-host-tuning.md). Give critical services a
better `oom_score_adj` (e.g. `-500`) so the DB isn't the first to die.

## Storage

- **Bind mounts over named volumes** for anything you want to back up or
  inspect — you can see it on the host and rsync it.
- Keep app data on a **separate filesystem/dataset** from the OS so a full
  disk doesn't wedge the whole box. Alert on fill *rate*, not just percent.
- Audit what's mounted where with
  [bind-mount-audit.sh](../scripts/bind-mount-audit.sh) — no writable
  `/`, `/etc`, `$HOME`, or `docker.sock` unless a container's whole job is
  managing the host.

## Power

- **UPS + NUT.** A dirty shutdown is how you learn your database didn't have
  `fsync` where you thought. `apt install nut`, set the host as `netserver`
  for the UPS, configure `upsmon` to shut down at ~30% battery. Test it by
  pulling the plug.
- Set `restart-on-power-restored` in BIOS/BMC so the box comes back on its own.

## Backups (3-2-1, and one of them encrypted + off-host)

- **3** copies, **2** media, **1** off-site.
- Local rotated copy: [backup-rotate.sh](../scripts/backup-rotate.sh).
- Databases: [stack-db-dump.sh](../scripts/stack-db-dump.sh) (never rsync a
  live DB file — dump it).
- Off-host encrypted: [age-backup.sh](../scripts/age-backup.sh) to another
  machine, a NAS, or object storage. The private key lives **only** offline.
- **Test a restore.** An untested backup is a hope. See
  [backup-restore-drill.md](backup-restore-drill.md).

## Config in git

Compose files, `/etc` snapshots, reverse-proxy config, dashboards, cron —
commit all of it and push off-host nightly with
[nightly-git-mirror.sh](../scripts/nightly-git-mirror.sh). Keep secrets out
([config-as-code-repo-hygiene.md](config-as-code-repo-hygiene.md)). When the
box dies, "clone, fill in `.env`, `docker compose up`" is the whole recovery.

## Know when it's sick

Minimal monitoring that actually pages you:

- **Uptime Kuma** (one container) for "is each service answering" + a push
  notification. Zero config beyond adding monitors.
- Prometheus + node-exporter + cAdvisor + Grafana if you want history and
  trends; the alerts that matter are: host down, disk will fill in <24h,
  a mount is gone, a container is OOM-near or crash-looping, a cert expires
  in <14d. See [monitoring-alerting-guide.md](monitoring-alerting-guide.md).

## The drill

Once a quarter: pull the UPS, confirm clean shutdown and auto-return; restore
one database and one app's data into a scratch dir and diff; `git clone` the
config repo somewhere fresh and confirm it's complete.
