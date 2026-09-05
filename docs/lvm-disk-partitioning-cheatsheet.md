# LVM & Disk Partitioning Cheatsheet

For the non-ZFS case: plain partitions, ext4/xfs, and LVM when you want
resizable volumes without a full ZFS stack. See [zfs-cheatsheet.md](zfs-cheatsheet.md)
for the alternative when the pool needs snapshots, checksumming, or
built-in redundancy.

## Identify what's there before touching anything

```bash
lsblk -f                       # disks, partitions, filesystem, UUID, mountpoint
blkid                          # UUIDs and filesystem types, one line per device
fdisk -l                       # partition tables, including unpartitioned disks
findmnt                        # currently mounted filesystems as a tree
df -hT                         # mounted filesystems, usage, and type
```

## Partitioning (parted, GPT-aware)

```bash
parted /dev/sdb print                                  # show existing table
parted /dev/sdb mklabel gpt                             # new GPT table (destroys data)
parted -a optimal /dev/sdb mkpart primary ext4 0% 100%  # one partition, full disk
partprobe /dev/sdb                                      # re-read the partition table
```
`fdisk /dev/sdb` (interactive, MBR or GPT) is the other common path — `n`
for new, `p` to print, `w` to write. Nothing is written to disk until `w`;
`q` aborts safely.

## Filesystems

```bash
mkfs.ext4 /dev/sdb1
mkfs.xfs /dev/sdb1
tune2fs -l /dev/sdb1                     # ext4 superblock info
xfs_info /mnt/data                       # xfs info (needs an active mount)
e2fsck -f /dev/sdb1                      # ext4 check/repair (unmount first)
xfs_repair /dev/sdb1                     # xfs check/repair (unmount first)
resize2fs /dev/sdb1                      # grow ext4 to fill the partition
xfs_growfs /mnt/data                     # grow xfs (online, mounted)
```
xfs can only grow, never shrink — plan partition sizes accordingly, or use
LVM underneath so growing means extending the logical volume, not the
partition.

## LVM: physical volumes -> volume groups -> logical volumes

```bash
pvcreate /dev/sdb1                       # mark a partition as an LVM PV
vgcreate data-vg /dev/sdb1               # create a VG from one or more PVs
vgextend data-vg /dev/sdc1               # add another disk to the pool later
lvcreate -L 100G -n app-lv data-vg       # fixed-size LV
lvcreate -l 100%FREE -n app-lv data-vg   # use all remaining space in the VG

pvs; vgs; lvs                            # summary at each layer
pvdisplay; vgdisplay; lvdisplay          # full detail at each layer
```

## Growing an LVM volume (the common day-2 operation)

```bash
vgextend data-vg /dev/sdd1                            # add capacity to the VG
lvextend -L +50G /dev/data-vg/app-lv                  # grow the LV
lvextend -l +100%FREE /dev/data-vg/app-lv             # or: use all free space in the VG

resize2fs /dev/data-vg/app-lv                         # then grow the ext4 filesystem
xfs_growfs /mnt/app                                   # or grow xfs (mounted, by mountpoint)
```
`lvextend -r` does the filesystem resize automatically for ext2/3/4 and
xfs in one step — worth using instead of the two separate commands above.

## Snapshots (LVM thin or classic — for a consistent point-in-time copy, not a backup)

```bash
lvcreate -L 5G -s -n app-snap /dev/data-vg/app-lv     # classic COW snapshot
mount -o ro /dev/data-vg/app-snap /mnt/snap           # mount read-only to back it up
lvremove /dev/data-vg/app-snap                        # remove once done
```
A classic snapshot fills up (and auto-drops) if the source changes more
than the snapshot's allocated size before it's removed — size it for the
churn expected during the backup window, not just the data size.

## Mounting and fstab

```bash
blkid /dev/data-vg/app-lv                 # get the UUID
mount UUID=<uuid> /mnt/app                # mount by UUID (survives device renumbering)
```
`/etc/fstab` line, by UUID (preferred over `/dev/sdX`, which can shift
across reboots):
```
UUID=<uuid>  /mnt/app  ext4  defaults,noatime  0  2
```
```bash
mount -a          # test fstab entries without rebooting
findmnt --verify  # validate fstab syntax and mount state
```

## Swap

```bash
fallocate -l 4G /swapfile          # or: dd if=/dev/zero of=/swapfile bs=1M count=4096
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
swapon --show                      # active swap devices/files
```
`/etc/fstab` entry: `/swapfile none swap sw 0 0`.

## Notes

- Always re-check `lsblk`/`blkid` immediately before an `mkfs`/`parted`
  command against a specific device path — device names (`/dev/sdb` etc.)
  can shift between boots, especially after adding/removing disks.
- LVM adds a layer of indirection that pays for itself the first time a
  volume needs to grow without downtime; it's not needed for a single
  disk that will never be resized.
- `wipefs -a /dev/sdX` clears stale filesystem/LVM/RAID signatures from a
  disk being repurposed — do this before `pvcreate`/`mkfs` on a disk that
  previously held something else, or the old signature can confuse tools
  that auto-detect filesystem type.
