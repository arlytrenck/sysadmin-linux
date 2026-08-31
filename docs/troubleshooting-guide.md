# Common Troubleshooting Guide

Quick reference for frequently-needed diagnostics on a Linux server.

## Disk space

```bash
df -hP                      # per-filesystem usage
du -xh --max-depth=2 / | sort -rh | head -20   # largest top-level dirs
lsof +L1                    # deleted-but-still-open files holding space
```

If `df` and `du` disagree wildly, look for a deleted file still held open
by a process (common with log files a service still has a handle on) —
`lsof +L1` will show it; restarting the offending service frees the space.

## Memory pressure

```bash
free -h
ps aux --sort=-%mem | head -10
dmesg -T | grep -i "out of memory"
```

## High CPU

```bash
top -o %CPU
pidstat 1 5          # per-process, sampled
```

## A service won't start

```bash
systemctl status <unit>
journalctl -u <unit> -n 100 --no-pager
systemctl show <unit> -p ExecStart      # confirm what it's actually running
```

Check for a config syntax error first — most daemons will tell you if you
run them with a `-t`/`--test`/`configtest` flag (nginx, sshd, and many
others support this).

## Networking

```bash
ss -tulpn                   # listening ports and owning process
ip a                        # interfaces and addresses
ip route                    # routing table
curl -v telnet://host:port  # basic reachability/port test without netcat
dig +short example.com      # DNS resolution
```

## Permissions / "Permission denied"

```bash
namei -l /path/to/file      # walk the full path showing perms at each level
getfacl /path/to/file       # ACLs, if in use
ls -ldZ /path/to/file       # SELinux context, on systems that use it
```

## Package manager is stuck / locked

```bash
# apt
sudo fuser -vki /var/lib/dpkg/lock-frontend
sudo dpkg --configure -a

# dnf/yum
sudo rm -f /var/run/yum.pid
```

Only remove a lock file after confirming no package operation is actually
in progress (`ps aux | grep -E 'apt|dpkg|dnf|yum'`).

## Boot problems

```bash
journalctl -b -1 -p err     # errors from the previous boot
systemctl list-jobs         # units still starting/stuck at boot
systemd-analyze blame       # what's slow at boot
systemd-analyze critical-chain
```

