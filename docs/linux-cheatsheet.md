# Linux Cheatsheet

## Processes & load
```bash
ps -eo pid,ppid,ni,pcpu,pmem,etimes,comm --sort=-pcpu | head    # top CPU
ps -eo pid,rss,comm --sort=-rss | head                          # top RAM (RSS in KB)
uptime                       # load avg: 1 / 5 / 15 min — compare to nproc
nproc                        # cores; load > cores sustained = saturated
kill -TERM <pid>; kill -KILL <pid>   # ask nicely, then don't
pkill -f 'pattern'           # by command line
nice -n 19 cmd ; renice 19 -p <pid>  # deprioritise batch work
```
`load` counts running **and** uninterruptible (D-state, usually I/O) tasks — a
high load with low CPU% means you're I/O-bound, not CPU-bound.

## Files & space
```bash
du -xh --max-depth=1 /var | sort -h        # what's big, one filesystem
find / -xdev -type f -size +500M 2>/dev/null
df -hT                                       # -T shows fstype
ncdu /var                                    # interactive if available
lsof +L1                                     # deleted-but-open files eating space
truncate -s 0 big.log                        # empty a log without breaking the writer's fd
```
Disk full but `du` doesn't add up → a process holds a deleted file open
(`lsof +L1`); restart it or `: > /proc/<pid>/fd/<n>`.

## Permissions
```bash
stat -c '%A %U:%G %n' file
chmod 640 file ; chmod u=rw,g=r,o= file
setfacl -m u:alice:rX dir ; getfacl dir
chattr +i file        # immutable (root only), lsattr to see
umask 027             # new files 640, dirs 750
```

## journald / logs
```bash
journalctl -u nginx -f                 # follow a unit
journalctl -u nginx --since '1 hour ago' --no-pager
journalctl -p err -b                    # this boot, error+ priority
journalctl --disk-usage ; journalctl --vacuum-size=200M
journalctl -k                           # kernel ring buffer (dmesg)
```
Cap it permanently in `/etc/systemd/journald.conf`: `SystemMaxUse=200M`.

## Users & sudo
```bash
id alice ; groups alice
usermod -aG docker alice        # add to group (log out/in to take effect)
sudo -n true 2>/dev/null && echo passwordless   # test without prompting
visudo -f /etc/sudoers.d/90-alice   # never edit /etc/sudoers directly
```

## Disks / mounts
```bash
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,SERIAL
blkid                                  # UUIDs for fstab
findmnt -A                             # tree of mounts
mount -o remount,rw /                  # flip a ro mount
# fstab: use UUID=, add nofail for removable/optional, noatime for SSD/CIFS
```

## Quick health sweep
```bash
uptime; free -h; df -hT | grep -vE 'tmpfs|overlay'
systemctl --failed
journalctl -p warning -b --no-pager | tail -30
ss -tlnp
```
