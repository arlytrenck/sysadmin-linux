# ZFS Cheatsheet

## Pools
```bash
zpool status -v            # health, errors, scrub state — read this first
zpool list -v              # capacity per vdev
zpool import               # list importable pools ; zpool import <name>
zpool history <pool>       # every admin action ever taken
zpool iostat -v 2          # live per-vdev I/O
```
Keep pools under ~80–85% full — allocation gets slow and fragmented past that.

## Redundancy reality check
- `RAID0` / a pool of single-disk vdevs = **no** redundancy; one disk lost = pool
  lost. Fine only for scratch or a *monitored, rebuildable* copy.
- mirror = survive 1 loss per mirror vdev, fast resilver.
- raidz1/2/3 = survive 1/2/3 losses per raidz vdev, slower resilver, no vdev
  expansion on older ZFS.
A backup on a no-redundancy array still needs its own monitoring and a plan for
"the array died" — the copy is not the safety net if losing it is silent.

## Datasets
```bash
zfs list -o name,used,avail,refer,mountpoint
zfs create pool/data
zfs set compression=zstd atime=off pool/data
zfs set quota=100G refquota=90G pool/data
zfs get all pool/data | grep -v default
```

## Snapshots & clones
```bash
zfs snapshot pool/data@$(date +%F-%H%M)
zfs list -t snapshot -o name,used,creation
zfs rollback pool/data@snap            # destroys newer snaps; -r to force
zfs diff pool/data@snap pool/data      # what changed since
zfs clone pool/data@snap pool/data-test
zfs destroy pool/data@snap
```
Automate with `zfs-auto-snapshot` or `sanoid`. Snapshots are not backups until a
copy leaves the box.

## Replication (real off-box backup)
```bash
zfs send -R pool/data@snap | ssh backup 'zfs recv -Fu tank/data'      # full
zfs send -I @old @new pool/data | ssh backup 'zfs recv tank/data'     # incremental
```
`syncoid` (from sanoid) wraps this with resume, bookmarks, and pruning.

## Scrub (catch bit-rot before a resilver needs the data)
```bash
zpool scrub <pool>            # run monthly; watch progress in zpool status
zpool scrub -s <pool>         # stop
```
Schedule via a systemd timer or the distro's `zfs-scrub@.timer`.

## ARC (RAM cache)
```bash
arc_summary          # or: cat /proc/spl/kstat/zfs/arcstats
# cap it (leaves RAM for VMs/apps) — /etc/modprobe.d/zfs.conf:
#   options zfs zfs_arc_max=8589934592        # 8 GiB
# live (until reboot):
echo 8589934592 > /sys/module/zfs/parameters/zfs_arc_max
```

## Replacing a failed disk
```bash
zpool status                       # note the DEGRADED device id
zpool replace <pool> <old-id> /dev/disk/by-id/<new>
zpool status                       # watch resilver; don't reboot mid-resilver
```
Use `/dev/disk/by-id/` (stable) names when creating pools, never `/dev/sdX`.

## Feature flags / upgrades
`zpool upgrade` is one-way and can block importing the pool on an older kernel —
leave it until the new OS has been stable for a while and you no longer need the
rollback path.
