# SSH Hardening Reference

Concrete `sshd_config` settings referenced by the hardening checklist, with
the reasoning behind each one. Test every change with `sshd -t` before
reloading, and keep an existing session open until you've confirmed a new
connection works — a bad `sshd_config` can lock you out.

## Baseline settings

```
# Disable root login over SSH entirely. Use sudo from a named account instead.
PermitRootLogin no

# Key-based auth only — no passwords to brute-force.
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes

# Don't allow empty passwords, ever, regardless of the above.
PermitEmptyPasswords no

# Limit protocol to SSH2 (default on any modern OpenSSH, but explicit is fine).
Protocol 2

# Cap authentication attempts and the grace period for completing login.
MaxAuthTries 4
LoginGraceTime 30

# Disable X11 forwarding unless you specifically need it.
X11Forwarding no

# Restrict which users/groups may connect, if your environment allows it.
# AllowUsers deploy admin
# AllowGroups sshusers
```

## Applying changes

```bash
sudo visudo -f /etc/ssh/sshd_config    # or your editor of choice on the real file
sudo sshd -t                           # validate syntax before reloading
sudo systemctl reload sshd
```

`sshd -t` catches syntax errors but not logical ones (e.g., locking out the
only account with keys configured) — always keep a second session open
while testing.

## Key management

- Generate keys with `ssh-keygen -t ed25519` (Ed25519 is preferred over RSA
  for new keys — smaller, faster, and considered at least as secure at
  typical key sizes).
- Store `authorized_keys` with `600` permissions and the `.ssh` directory
  with `700`, owned by the user — sshd will silently refuse loose
  permissions.
- Prefer one key per person per device over shared keys, so a compromised
  laptop doesn't mean rotating a key used everywhere.
- Rotate and remove keys when someone leaves or a device is retired —
  `user-activity-report.sh` and a periodic `authorized_keys` review both
  help catch stale entries.

## Fail2ban (optional but common)

```bash
sudo apt install fail2ban   # or: sudo dnf install fail2ban
```

Minimal `/etc/fail2ban/jail.local`:

```
[sshd]
enabled = true
maxretry = 5
bantime = 1h
findtime = 10m
```

## Bastion / jump-host pattern

For fleets larger than a handful of hosts, consider routing SSH through a
single hardened bastion (`ProxyJump` in `~/.ssh/config`) rather than
exposing every host's port 22 to the internet directly:

```
Host bastion
  HostName bastion.example.com
  User deploy

Host internal-*
  ProxyJump bastion
  User deploy
```

