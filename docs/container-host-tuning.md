# Container Host Tuning Reference

Kernel and runtime settings worth reviewing on a Linux box that runs a lot of
containers — especially a VM whose committed memory limits sum well above
physical RAM. Every value below is a starting point; measure on your own
workload before treating any of it as correct. Apply via a drop-in and reload:

```bash
sudo tee /etc/sysctl.d/99-host-tuning.conf >/dev/null <<'EOF'
vm.swappiness = 10
vm.overcommit_memory = 1
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
EOF
sudo sysctl --system
```

## Memory

| setting | suggested | why |
|---|---|---|
| `vm.swappiness` | `10` | With many containers, the default `60` swaps out warm anonymous pages too eagerly and adds latency. Low but non-zero keeps a safety valve. |
| `vm.overcommit_memory` | `1` | If the sum of per-container `mem_limit`s is much larger than RAM (normal — most never hit their ceiling), strict accounting (`0`/`2`) causes spurious `fork`/`mmap` failures. `1` lets the kernel overcommit and rely on the OOM killer as the backstop. |
| `vm.vfs_cache_pressure` | `50` | Keeps dentry/inode cache around longer, which helps image layers and bind mounts with lots of small files. |

If you set `overcommit_memory = 1`, **you must have real per-container limits**
(`mem_limit` / `deploy.resources.limits`) so one runaway service is OOM-killed
instead of the host. Also consider `oom_score_adj` on anything critical.

## Writeback

| setting | suggested | why |
|---|---|---|
| `vm.dirty_ratio` | `10` | The default `20` lets a large fraction of RAM fill with dirty pages before forcing synchronous writeback — a painful stall on spinning disks or slow virtual storage. |
| `vm.dirty_background_ratio` | `5` | Start flushing in the background earlier so the synchronous limit is rarely hit. |

Lower these further (e.g. `5` / `2`) if the storage is slow or shared; leave
the defaults on fast local NVMe.

## inotify

Containers running file watchers (dev servers, log shippers, `*arr`-style
apps, syncthing) exhaust the per-user defaults fast, which shows up as
"too many open files" or watchers silently not firing.

```
fs.inotify.max_user_watches   = 524288
fs.inotify.max_user_instances = 512
```

## Transparent huge pages

Databases (PostgreSQL, Redis, MongoDB, Elasticsearch) generally want THP set
to `madvise` or `never`, not `always` — `always` causes allocation stalls and
memory bloat for their access patterns.

```bash
cat /sys/kernel/mm/transparent_hugepage/enabled     # check
# persist: add "transparent_hugepage=madvise" to the kernel cmdline, or a
# tmpfiles.d / systemd unit that writes the sysfs file at boot.
```

## Filesystem mount options

- `noatime` on the root and data filesystems removes a metadata write on
  every read. `relatime` (the modern default) is already most of the way
  there; `noatime` closes the gap for read-heavy container workloads.

```bash
# /etc/fstab — add noatime to the options column, then:
sudo mount -o remount /
```

## Journald

Container logs go through the Docker json-file driver (cap it in
`daemon.json`), but the host journal still grows. Cap it:

```bash
sudo tee /etc/systemd/journald.conf.d/00-size.conf >/dev/null <<'EOF'
[Journal]
SystemMaxUse=500M
EOF
sudo systemctl restart systemd-journald
```

And in `/etc/docker/daemon.json`:

```json
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "5" },
  "live-restore": true
}
```

## Verifying

```bash
sysctl vm.swappiness vm.overcommit_memory vm.dirty_ratio
cat /proc/pressure/{memory,io}          # PSI — is the host actually stalling?
docker stats --no-stream                # per-container mem vs. limit
```

Pairs with [container-security-guide.md](container-security-guide.md) and
[docker-container-audit.sh](../scripts/docker-container-audit.sh).
