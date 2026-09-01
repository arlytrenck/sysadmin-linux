# systemd Cheatsheet

Common `systemctl` and `journalctl` commands for day-to-day service
management, grouped by task.

## Service state

```bash
systemctl status <unit>              # current state + recent log lines
systemctl is-active <unit>           # just the state, for scripting
systemctl is-enabled <unit>          # will it start at boot?
systemctl list-units --type=service --state=running
systemctl --failed                   # everything currently in a failed state
```

## Starting, stopping, restarting

```bash
systemctl start <unit>
systemctl stop <unit>
systemctl restart <unit>             # stop then start
systemctl reload <unit>              # re-read config without a full restart, if supported
systemctl reload-or-restart <unit>   # reload if supported, else restart
```

## Enabling at boot

```bash
systemctl enable <unit>              # start at boot
systemctl disable <unit>             # don't start at boot
systemctl enable --now <unit>        # enable and start in one step
systemctl mask <unit>                # prevent it from being started at all, even manually
systemctl unmask <unit>
```

## Logs

```bash
journalctl -u <unit>                 # all logs for a unit
journalctl -u <unit> -f              # follow, like tail -f
journalctl -u <unit> --since "1 hour ago"
journalctl -u <unit> -p err          # errors and above only
journalctl -b                        # logs since last boot
journalctl -b -1                     # logs from the previous boot
journalctl --disk-usage              # how much space the journal is using
journalctl --vacuum-time=7d          # prune logs older than 7 days
```

## Timers (systemd's cron alternative)

```bash
systemctl list-timers                # all active timers and next run time
systemctl status <name>.timer
journalctl -u <name>.service         # the timer's associated job logs here, not the timer itself
```

Minimal timer pair:

```ini
# /etc/systemd/system/backup.service
[Unit]
Description=Run backup script

[Service]
Type=oneshot
ExecStart=/usr/local/bin/backup-rotate.sh -s /data -d /backups
```

```ini
# /etc/systemd/system/backup.timer
[Unit]
Description=Daily backup

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
systemctl daemon-reload
systemctl enable --now backup.timer
```

## Inspecting unit files

```bash
systemctl cat <unit>                 # print the effective unit file
systemctl show <unit> -p ExecStart   # one specific property
systemctl edit <unit>                # create an override drop-in (preferred over editing the original)
systemctl list-dependencies <unit>
```

## Boot performance

```bash
systemd-analyze                      # total boot time
systemd-analyze blame                # slowest units to start
systemd-analyze critical-chain       # the critical path that determined boot time
```

## Editing units the right way

Never edit files in `/lib/systemd/system` or `/usr/lib/systemd/system` — they
get overwritten on package upgrade. Use a drop-in:

```bash
systemctl edit foo         # creates /etc/systemd/system/foo.service.d/override.conf
systemctl daemon-reload
systemctl restart foo
```

Full replacement (rare): `systemctl edit --full foo`. A drop-in only needs the
keys you change. To clear a list-valued key inherited from the vendor unit, set
it empty first:

```ini
[Service]
ExecStart=
ExecStart=/usr/bin/foo --new-flags
```

## Resource control (cgroups v2)

Put limits in a drop-in or the unit — this caps the *service*, so a leak
OOM-kills the unit instead of the host:

```ini
[Service]
MemoryMax=2G            # hard cap
MemoryHigh=1500M        # soft pressure (throttle before the cap)
CPUQuota=200%           # = 2 cores
TasksMax=4096
IOWeight=50
```

Inspect live: `systemctl status foo` shows the cgroup; `systemd-cgtop` ranks
units by resource use. Test an `OnCalendar=` expression with
`systemd-analyze calendar 'Mon *-*-1..7 02:00'`.

## Sandboxing a service (defense in depth)

```ini
[Service]
NoNewPrivileges=true
ProtectSystem=strict           # most of the filesystem read-only
ProtectHome=true
PrivateTmp=true
ReadWritePaths=/var/lib/foo    # carve back only what the service must write
CapabilityBoundingSet=         # drop all capabilities; add back only what's needed
SystemCallFilter=@system-service
```

`systemd-analyze security foo` scores a unit's exposure and shows which of these
knobs are unset.
