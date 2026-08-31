# Server Hardening Checklist

A working checklist for bringing a freshly-provisioned Linux server to a
reasonable baseline security posture. Not exhaustive — adapt to your threat
model and compliance requirements.

## Access

- [ ] Disable direct root SSH login (`PermitRootLogin no` in `sshd_config`)
- [ ] Disable password authentication for SSH (`PasswordAuthentication no`);
      use key-based auth only
- [ ] Change the default SSH port only if it meaningfully reduces noise for
      your setup (not a substitute for the above)
- [ ] Create a named admin user with sudo, rather than sharing root
- [ ] Enforce MFA for any web-facing admin panels
- [ ] Review and prune unused user accounts and stale SSH keys regularly

## Network

- [ ] Enable a host firewall (ufw/firewalld/nftables) with a default-deny
      inbound policy
- [ ] Only open ports that are actually in use
- [ ] Rate-limit or fail2ban SSH and any other exposed auth endpoints
- [ ] Disable unused network services (`systemctl list-unit-files --state=enabled`)

## System

- [ ] Enable automatic security updates (`unattended-upgrades` on
      Debian/Ubuntu, `dnf-automatic` on Fedora/RHEL)
- [ ] Set a consistent timezone and enable NTP (`timedatectl`)
- [ ] Configure log rotation for all application logs
- [ ] Ship logs off-host (syslog forwarding, journald forwarding, or an
      agent) so an attacker can't erase local evidence
- [ ] Set sane `umask` defaults and review world-writable directories
      (`find / -xdev -type d -perm -0002`)

## Monitoring

- [ ] Set up disk, memory, and CPU alerting thresholds
- [ ] Monitor for failed login attempts (`journalctl -u sshd` /
      `/var/log/auth.log`)
- [ ] Track package/config drift if you manage more than a couple of hosts
- [ ] Confirm backups are actually running and are restorable (test restores
      periodically, not just backup job success)

## Before Going Live

- [ ] Run a basic port scan from outside the host to confirm only intended
      ports are reachable
- [ ] Confirm `sshd_config` changes with `sshd -t` before reloading
- [ ] Document the host's purpose, owner, and any non-standard configuration
      in this repo's runbook

