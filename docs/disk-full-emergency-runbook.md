# Disk Full Emergency Runbook

A filesystem at or near 100%: services failing to write, databases going
read-only, logins hanging. This is the "stop the bleeding" procedure. See
also [disk-usage-report.sh](../scripts/disk-usage-report.sh) and
[log-cleanup.sh](../scripts/log-cleanup.sh).

## 0. Confirm and locate

```bash
df -hP                       # which filesystem, how full
df -iP                       # inodes — "no space left" with free bytes = inode exhaustion
mount | grep -w "$(df -P /path | awk 'NR==2{print $6}')"   # which device
```

If `/` itself is 100%, even simple commands may fail. Free a little
breathing room first (see step 2), then investigate properly.

## 1. Find the space

```bash
# biggest directories under the full mount, one level at a time
du -x -h -d1 /var 2>/dev/null | sort -h | tail
du -x -h -d1 /var/log /var/lib 2>/dev/null | sort -h | tail

# biggest individual files
find /var -xdev -type f -printf '%s\t%p\n' 2>/dev/null | sort -rn | head -20 | numfmt --field=1 --to=iec

# fast whole-tree view if installed
ncdu -x /var
```

`-x` / `-xdev` keeps `du`/`find` on one filesystem so you don't chase
`/proc`, `/sys`, or other mounts.

### The classic culprit: a deleted-but-open file

A log rotated or deleted while a process still holds it open: space isn't
freed until the process closes it. `du` won't see it; `df` still counts it.

```bash
sudo lsof -nP +L1 | sort -k7 -rn | head        # open files with link count 0
sudo lsof -nP | grep '(deleted)' | awk '{print $2, $NF}' | sort -u
```

Fix: restart the holding process, or truncate via its fd without restarting:

```bash
sudo truncate -s 0 "/proc/<pid>/fd/<n>"        # for a deleted logfile still being written
```

## 2. Safe things to delete/reclaim, in order

```bash
# systemd journal — usually the fastest win
journalctl --disk-usage
sudo journalctl --vacuum-size=200M       # or --vacuum-time=7d
sudo sed -i 's/^#\?SystemMaxUse=.*/SystemMaxUse=200M/' /etc/systemd/journald.conf
sudo systemctl restart systemd-journald

# package manager caches
sudo apt clean            # Debian/Ubuntu  (or: apt autoclean, apt autoremove --purge)
sudo dnf clean all        # RHEL/Fedora
sudo pacman -Scc          # Arch

# rotated / old logs
sudo find /var/log -type f -name '*.gz' -mtime +14 -delete
sudo find /var/log -type f -regextype posix-extended -regex '.*\.[0-9]+$' -mtime +14 -delete
: > /var/log/huge-noisy.log      # truncate, don't rm, a file that's still open

# old kernels (Debian/Ubuntu) — keep the running one + one spare
sudo apt autoremove --purge
uname -r     # never remove this one

# crash dumps / core files
sudo rm -f /var/crash/* /var/lib/systemd/coredump/*
```

### Docker hosts

```bash
docker system df                       # where docker's space went
docker system prune                    # dangling images, stopped containers, unused networks
docker system prune -a --volumes       # AGGRESSIVE: also unused images + unused volumes — read the prompt
docker builder prune                   # build cache (often gigabytes)
docker logs --tail 0 <c> 2>/dev/null   # can't truncate directly; set log rotation instead
sudo truncate -s 0 /var/lib/docker/containers/*/*-json.log   # last resort, per-container logs
```

Then set `log-opts` (`max-size`, `max-file`) in `/etc/docker/daemon.json` so
container logs can't do this again.

### Databases

A database that filled the disk often left WAL/binlog/transaction files. Do
**not** delete those by hand. Free space *elsewhere* first, get the DB
writable again, then let it check-point / archive:

```bash
# PostgreSQL: check pg_wal size; a stuck archive_command or an orphaned
# replication slot is the usual cause
du -sh $PGDATA/pg_wal
psql -c "select slot_name, active, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) from pg_replication_slots;"
# drop a dead slot only if you're sure the replica is gone:
psql -c "select pg_drop_replication_slot('deadslot');"
```

## 3. If you truly cannot free anything on that mount

- **Grow the filesystem** if it's on LVM / a cloud volume / thin pool:
  ```bash
  sudo lvextend -r -L +5G /dev/vg/lv            # -r resizes the FS too (ext4/xfs)
  # xfs: sudo xfs_growfs /mount ;  ext4: sudo resize2fs /dev/vg/lv
  ```
- **Move a big directory to another filesystem** and bind-mount / symlink it
  back (e.g. `/var/lib/docker`, `/var/log`, a data dir):
  ```bash
  sudo systemctl stop docker
  sudo rsync -aHAX --numeric-ids /var/lib/docker/ /mnt/data/docker/
  sudo mv /var/lib/docker /var/lib/docker.old && sudo mkdir /var/lib/docker
  echo '/mnt/data/docker /var/lib/docker none bind 0 0' | sudo tee -a /etc/fstab
  sudo mount -a && sudo systemctl start docker    # verify, then rm docker.old
  ```
- **Reserved blocks** on ext4 give root ~5% headroom you can temporarily
  lend: `sudo tune2fs -m 1 /dev/vg/lv` (set back to `5` after).

## 4. Verify and recover services

```bash
df -hP /path
systemctl --failed
# restart anything that went read-only / crashed while the disk was full
sudo systemctl restart <db> <app> ...
journalctl -p err -b | tail
```

Databases may need an explicit restart to leave read-only / recovery mode.

## 5. Prevent the recurrence

- Alert on disk at **80%** and on the **fill rate** (projected-full-in-Nh),
  not just a hard threshold. See
  [monitoring-alerting-guide.md](monitoring-alerting-guide.md).
- Cap the journal (`SystemMaxUse=`) and Docker logs (`daemon.json`).
- Put a `logrotate` policy on any app that writes its own logs.
- Give databases their own filesystem so a runaway table can't take down the
  OS.
- Watch inodes too (millions of tiny files: mail queues, session dirs,
  cache). A filesystem can hit 100% inodes at 30% bytes.
- Record what filled it in the change log / a
  [postmortem](incident-postmortem-template.md).
