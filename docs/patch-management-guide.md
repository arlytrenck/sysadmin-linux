# Patch Management Guide

A practical patching strategy for a small Linux fleet: enough process to
avoid both "we never patch" and "an unattended upgrade restarted the
database at 3am." Pairs with
[update-and-patch.sh](../scripts/update-and-patch.sh) (applying updates),
[pending-reboot-check.sh](../scripts/pending-reboot-check.sh) (confirming
a cycle actually finished), and
[package-inventory.sh](../scripts/package-inventory.sh) (diffing what
changed against a baseline).

The Windows companion to this document is
[patch-management-guide.md](https://github.com/arlytrenck/sysadmin-windows/blob/main/docs/patch-management-guide.md)
in sysadmin-windows. The ring model is the same; the tooling is not.

## Patch rings

Rolling every update to every host on the same day is how one bad
package takes down everything at once. A three-ring model:

1. **Canary** (one host, ideally a VM that matches production): day 0.
2. **Broad** (most of the fleet): a few days later, once nothing broke.
3. **Last-touch** (anything slow or expensive to recover — the
   hypervisor, the NAS, the box holding the only copy of something):
   last, after broad has run clean for a defined soak period.

48-72 hours of soak catches most "this update breaks X" reports, which
surface fast once a package is out in the wild.

## What "patched" actually means

Three separate things get conflated, and only the first is automatic on
most distros:

| Layer | Updated by | Restart needed |
|---|---|---|
| Userspace packages | `apt`/`dnf` | The affected service |
| Kernel, glibc, systemd | `apt`/`dnf` | Full reboot |
| Container images | Pulling a new tag/digest | `docker compose up -d` |

A host can be fully `apt upgrade`d and still be running the vulnerable
code, because the process that loaded the old library is still running.
`needrestart` (Debian/Ubuntu) and `dnf needs-restarting` (RHEL family)
are what close that gap:

```bash
# Debian/Ubuntu: what still runs old code, and which services to restart
sudo needrestart -r l

# RHEL family: which processes need restarting, and whether a reboot is due
sudo dnf needs-restarting
sudo dnf needs-restarting -r
```

[pending-reboot-check.sh](../scripts/pending-reboot-check.sh) wraps the
reboot half of this so a cron job can alert on it.

## Unattended upgrades, scoped to security only

Fully automatic upgrades of everything is how you find out at 3am that a
minor version bump changed a default. Automatic *security* updates, with
reboots left to a human, is the trade most small fleets want.

Debian/Ubuntu:

```bash
sudo apt install unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades

# /etc/apt/apt.conf.d/50unattended-upgrades - the lines that matter
Unattended-Upgrade::Allowed-Origins { "${distro_id}:${distro_codename}-security"; };
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Mail "root";

# Confirm it is actually running, rather than merely installed
systemctl status unattended-upgrades
sudo unattended-upgrade --dry-run --debug
```

RHEL family:

```bash
sudo dnf install dnf-automatic

# /etc/dnf/automatic.conf
[commands]
upgrade_type = security
apply_updates = yes
reboot = never

sudo systemctl enable --now dnf-automatic.timer
systemctl list-timers dnf-automatic.timer
```

Pin anything that must not move without a human deciding:

```bash
sudo apt-mark hold postgresql-16          # Debian/Ubuntu
echo 'exclude=kernel*' | sudo tee -a /etc/dnf/dnf.conf   # RHEL family
apt-mark showhold                          # audit what is pinned
```

A hold with no expiry is a package that quietly stops receiving security
fixes. Review the hold list every time you review the patch process.

## Before rolling out

- **Read the changelog**, not just the package version:
  `apt changelog <pkg>` or `dnf changelog <pkg>`.
- **Confirm a restore path exists first.** Run
  [backup-verify.sh](../scripts/backup-verify.sh) against the backup
  target before the canary, not after the failure.
- **Snapshot if the platform gives you one.** A ZFS snapshot or a
  hypervisor checkpoint turns a bad kernel into a five-minute rollback.
  See [zfs-cheatsheet.md](zfs-cheatsheet.md).
- **Record the baseline** so you can diff afterward:
  `./scripts/package-inventory.sh -o baseline-$(date +%F).txt`

## Applying updates

```bash
# Report only - what would change, no installation
./scripts/update-and-patch.sh -n

# Apply, logging what happened
./scripts/update-and-patch.sh -l /var/log/patching.log

# Did that actually finish, or is a reboot still pending?
./scripts/pending-reboot-check.sh
```

Reboot on your schedule rather than the package manager's. If the host
runs containers, confirm they came back with the right restart policy
rather than assuming:

```bash
sudo systemctl reboot
# after it returns
./scripts/service-health-check.sh
./scripts/healthcheck-audit.sh
```

## Container images are a separate patch stream

`apt upgrade` on the Docker host patches the host. It does nothing to the
software inside your containers, which is where most of your actually
exposed services live. That stream needs its own cadence:

```bash
# What is newer than the digest each stack has pinned?
./scripts/compose-image-updates.sh -d /srv/stacks

# Roll one stack, then confirm it came back healthy
docker compose -f /srv/stacks/media/compose.yaml pull
docker compose -f /srv/stacks/media/compose.yaml up -d
./scripts/healthcheck-audit.sh
```

Pinning to a digest rather than `:latest` is what makes this reviewable
at all — see
[docker-compose-hardening-cheatsheet.md](docker-compose-hardening-cheatsheet.md).

## After rolling out

- Diff the package set against the baseline you recorded:
  `./scripts/package-inventory.sh -d baseline-2026-09-01.txt`
- Confirm services are up, not merely "started":
  [service-health-check.sh](../scripts/service-health-check.sh).
- Watch the logs for the first hour of real traffic, not the first
  minute of an idle host:
  [log-anomaly-scan.sh](../scripts/log-anomaly-scan.sh).
- Confirm certificates and timers survived the reboot:
  [cert-expiry-check.sh](../scripts/cert-expiry-check.sh),
  [cron-audit.sh](../scripts/cron-audit.sh).

## Handling a bad patch

1. **Establish it is the patch.** Compare against the baseline diff. A
   coincidence is more common than people expect.
2. **Roll back the specific package**, not the whole cycle:
   ```bash
   sudo apt install <pkg>=<previous-version>   # Debian/Ubuntu
   sudo dnf downgrade <pkg>                    # RHEL family
   sudo dnf history undo <id>                  # or undo the transaction
   ```
3. **Hold it** so the next cycle does not reinstall it, and write down
   why. An unexplained hold gets removed by whoever inherits the box.
4. **Boot the previous kernel** from the GRUB menu if the kernel is the
   problem; it is still installed. Set it as default only long enough to
   get a fix, since old kernels stop getting security updates.
5. **Record it** in the change log so the same package does not get
   rolled out again in three weeks by someone who was not there. See
   [change-management-checklist.md](change-management-checklist.md).

## What to review quarterly

- The hold/exclude list — every pin, and whether it is still needed.
- Whether unattended-upgrades is still running (it silently stops if a
  dependency conflict wedges it).
- Whether anything in the fleet has fallen off a supported release. An
  end-of-life distro gets no security updates at all, which makes the
  rest of this document moot:
  `lsb_release -a`, `cat /etc/os-release`, `hostnamectl`.
