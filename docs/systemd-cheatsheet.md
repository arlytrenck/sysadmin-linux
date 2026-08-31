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

