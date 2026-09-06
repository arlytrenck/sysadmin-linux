# Cron & systemd Timers Cheatsheet

Scheduling on Linux: the several places a scheduled job can live, `crontab`
syntax and its traps, systemd timers, and **how to recover a crontab someone
overwrote**. See also [config-snapshots.md](config-snapshots.md) (back these
up) and [cron-audit.sh](../scripts/cron-audit.sh) (enumerate them all).

## Where scheduled jobs live

| Location | Whose | Edit with | Has a user field? |
|----------|-------|-----------|-------------------|
| `crontab -e` (per-user) | that user | `crontab -e` / `crontab -u NAME -e` | no |
| `/etc/crontab` | system | edit file directly | **yes** (col 6) |
| `/etc/cron.d/*` | system, per-package | edit file directly | **yes** |
| `/etc/cron.{hourly,daily,weekly,monthly}/*` | system | drop an executable script | n/a (run by `run-parts`) |
| systemd timers | system or user | `.timer` + `.service` units | n/a |
| `at` / `batch` | one-shot queue | `atq`, `atrm` | n/a |

Per-user crontabs are stored in `/var/spool/cron/crontabs/<user>` (Debian) or
`/var/spool/cron/<user>` (RHEL) — **root-owned, mode 600, do not edit
directly**; use `crontab`.

## crontab syntax

```
# ┌─ minute (0-59)
# │ ┌─ hour (0-23)
# │ │ ┌─ day of month (1-31)
# │ │ │ ┌─ month (1-12)
# │ │ │ │ ┌─ day of week (0-7, 0 and 7 = Sunday)
# │ │ │ │ │
  * * * * *  command to run
```

```cron
*/15 * * * *   every 15 minutes
0 */2 * * *    every 2 hours, on the hour
0 3 * * *      daily at 03:00
30 4 * * 1     04:30 every Monday
0 5 1 * *      05:00 on the 1st of every month
0 0 * * 1-5    midnight, weekdays only
@reboot       once, at boot
@daily        midnight (also @hourly @weekly @monthly @yearly)
```

Day-of-month and day-of-week are **OR'd** when both are restricted:
`0 0 13 * 5` runs on the 13th *and* every Friday, not "Friday the 13th".

## crontab gotchas

- **Minimal `PATH`** — cron runs with `PATH=/usr/bin:/bin`. Use absolute
  paths or set `PATH=` at the top of the crontab.
- **Not a login shell** — none of your `~/.bashrc` / `~/.profile` env exists.
  Set what you need explicitly (`SHELL=`, `PATH=`, `MAILTO=`, app vars).
- **`%` is special** — literal percent signs must be `\%` in a crontab command.
- **No output = silent** — cron mails stdout/stderr to `MAILTO` (or the user);
  if no MTA, it vanishes. Always redirect: `>> /var/log/job.log 2>&1`.
- **The file needs a trailing newline** — some crons silently skip the last
  line without one.
- **`crontab <file>` replaces the entire crontab.** No merge. See recovery
  below.
- **DST** — `cron` (Vixie) skips/repeats jobs across the spring/fall
  transition; systemd timers handle it correctly.
- Editing `/etc/cron.d/*` takes effect on the next minute; no reload needed.
  A syntax error in one file can block the whole file.

## Recovering an overwritten crontab

`crontab -r` (remove) and `crontab somefile` (replace) both wipe the previous
content with no undo. In order of preference:

**1. Config snapshot / backup.** If you snapshot `/etc` and `crontab -l`
output (you should — see [config-snapshots.md](config-snapshots.md)):

```bash
sudo crontab -u root -l                       # confirm what's there now
sudo crontab -u root /path/to/backup/crontab-root.txt   # restore
```

**2. The spool file's mtime and a filesystem backup.**

```bash
stat /var/spool/cron/crontabs/root            # when did it last change?
# restore that path from restic/borg/rsync/snapshot as of before that time
```

**3. Reconstruct from logs.** Cron logs every job it *starts*:

```bash
journalctl -u cron --since '-14 days' | grep CMD          # Debian
journalctl -u crond --since '-14 days' | grep CMD         # RHEL
grep CRON /var/log/syslog* 2>/dev/null | grep -oP '\(\K[^)]+\)(?= CMD \(.*\))' # users
grep -RhoP 'CMD \(\K[^)]+' /var/log/syslog* | sort -u     # the command lines
```

You get the commands and roughly when they ran (so you can infer the
schedule), but **not** the exact cron expression or any `VAR=` lines. Treat
it as a checklist to rebuild against, not a restore.

**4. Rebuild from the scripts themselves.** Well-written job scripts document
their intended schedule in their header comment. Grep for them:

```bash
grep -rl 'backup\|snapshot\|sync' /usr/local/sbin /opt /scripts 2>/dev/null
```

### Prevention

- Keep `crontab -l` output in your config-snapshot repo (`crontab -l >
  crontab-$(hostname).txt` in a snapshot script).
- Use a **managed block** so re-applies are idempotent and never clobber
  hand-added lines:

```bash
BEGIN='# >>> managed: backups >>>'; END='# <<< managed: backups <<<'
( crontab -l 2>/dev/null | sed "/$BEGIN/,/$END/d";
  printf '%s\n%s\n%s\n' "$BEGIN" "0 3 * * * /usr/local/sbin/backup.sh" "$END"
) | crontab -
```

- Prefer `/etc/cron.d/<name>` files for anything deployed by config
  management — they're version-controlled files, not opaque spool state.
- Alias to force safety: `alias crontab='crontab -i'` (prompts on `-r`).

## systemd timers

Two units: a `.timer` (when) and a matching `.service` (what).

```ini
# /etc/systemd/system/backup.service
[Unit]
Description=Nightly backup
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/backup.sh
```

```ini
# /etc/systemd/system/backup.timer
[Unit]
Description=Run backup nightly
[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true          # run on next boot if the machine was off at 03:00
RandomizedDelaySec=300   # jitter to avoid thundering herd
[Install]
WantedBy=timers.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now backup.timer
systemctl list-timers --all                 # next/last run for every timer
systemd-analyze calendar 'Mon *-*-* 03:00'   # validate + show next elapses
systemctl status backup.service              # last run's exit + logs
journalctl -u backup.service --since today
sudo systemctl start backup.service          # run it now, on demand
```

### Timers vs cron — why you might switch

- Real logging (`journalctl -u`), exit-status tracking, `systemctl status`.
- `Persistent=true` catches up missed runs after downtime; cron just skips.
- Resource control (`CPUQuota=`, `IOWeight=`, `MemoryMax=`) on the service.
- Dependency ordering (`After=`, `Requires=`), `OnFailure=` handlers.
- Correct DST handling.
- Downsides: two files per job, more verbose, `OnCalendar=` syntax differs
  from cron.

```bash
systemd-analyze calendar --iterations=5 'daily'   # cheat sheet for OnCalendar
```

## `at` — one-shot jobs

```bash
echo 'systemctl restart nginx' | at 02:00
at now + 1 hour -f script.sh
atq            # list pending
atrm 3         # cancel job 3
```
