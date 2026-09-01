# New Server Bootstrap Checklist

A day-0 checklist for a fresh Linux box before it does any real work. Order
matters — lock down access first, then build. This is the *procedure*; the
security-specific review it points to in step 5 is
[server-hardening-checklist.md](server-hardening-checklist.md).

## 1. Access
- [ ] Create a non-root user, add to the sudo/wheel group; give it your SSH key.
- [ ] `ssh` in as that user, `sudo -v` works. **Now** disable root login and
      password auth in `sshd_config`; `systemctl reload ssh`; keep the current
      session open while you test a new one.
- [ ] Firewall: default-deny inbound, allow SSH (from your admin range if you
      can) + whatever this box serves. `ufw`, `firewalld`, or nftables.
- [ ] Auto-block for SSH brute force (`fail2ban` / platform equivalent).

## 2. Baseline system
- [ ] `apt update && apt full-upgrade` (or dnf), reboot if the kernel changed.
- [ ] Set hostname, timezone (`timedatectl set-timezone …`), and confirm NTP is
      syncing (`timedatectl` → "System clock synchronized: yes").
- [ ] Unattended security updates (`unattended-upgrades` / `dnf-automatic`) —
      security only, notify on the rest.
- [ ] Swap: present and sane (or a swapfile); `vm.swappiness=10` for a server.
- [ ] Journald capped (`/etc/systemd/journald.conf`: `SystemMaxUse=200M`).

## 3. Observability (so problems aren't invisible)
- [ ] A metrics agent (node_exporter / netdata / the platform's) reachable by
      your monitoring, bound to an internal interface.
- [ ] Log shipping if you centralize logs.
- [ ] Alerting wired for: disk >85%, load sustained > cores, a service down,
      cert expiry, backup age. Untested alerting = no alerting.

## 4. Backups (before there's data to lose)
- [ ] Decide what's backed up (data + config), to where, how often, encrypted.
- [ ] Config into a private git repo or a `git bundle` in the encrypted archive.
- [ ] Schedule it (systemd timer), and schedule the **verify**
      ([../scripts/backup-verify.sh](../scripts/backup-verify.sh)).
- [ ] Do one real restore now, while it's cheap.

## 5. Hardening pass
- [ ] Work through [server-hardening-checklist.md](server-hardening-checklist.md)
      — passwordless-sudo review, unexpected listening ports, SSH baseline,
      package/service pruning, `sysctl` baseline, optional `auditd` +
      AppArmor/SELinux enforcing.

## 6. Document it
- [ ] Snapshot the config
      ([../scripts/system-snapshot.sh](../scripts/system-snapshot.sh)) and commit it.
- [ ] One page: what this box is, what runs on it, how to reach it, where its
      backups are, who to tell if it's down. Future-you will thank present-you.
