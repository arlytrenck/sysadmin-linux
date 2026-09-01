# SSH Cheatsheet

Client and server quick reference: keys, agent, `~/.ssh/config`, tunnels, file
transfer, and debugging. For the `sshd_config` hardening baseline and the
reasoning behind each setting, see
[ssh-hardening-reference.md](ssh-hardening-reference.md).

## Keys
```bash
ssh-keygen -t ed25519 -C 'me@laptop'          # ed25519, not RSA, in 2020s
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_work -C 'work'   # a dedicated key
ssh-copy-id -i ~/.ssh/id_ed25519.pub user@host
ssh-keygen -lf ~/.ssh/id_ed25519.pub          # fingerprint
```
No passphrase → protect the file (`chmod 600`) and only put it where it's needed.
With a passphrase → use `ssh-agent`.

## Agent
```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519            # add (with timeout: ssh-add -t 1h)
ssh-add -l                          # list loaded keys
ssh -A host                         # forward the agent (only to hosts you trust)
```

## `~/.ssh/config` — stop typing flags
```
Host prod
    HostName 203.0.113.10
    User deploy
    IdentityFile ~/.ssh/id_ed25519_work
    IdentitiesOnly yes            # don't offer every key (avoids lockouts)

Host *.internal
    ProxyJump bastion            # hop through a jump host automatically
    ServerAliveInterval 30

Host bastion
    HostName bastion.example.com
    User me
```
Then just `ssh prod`. `IdentitiesOnly yes` matters when you have many keys.

## Tunnels
```bash
ssh -L 8080:127.0.0.1:80 host      # local:  localhost:8080 -> host's :80
ssh -R 9000:127.0.0.1:3000 host    # remote: host's :9000 -> your :3000
ssh -D 1080 host                   # SOCKS proxy through host
ssh -fN -L ...                     # background, no shell
```

## Move files
```bash
scp file host:/path/                     # simple
rsync -avP --delete src/ host:/dst/      # resumable, mirrors, shows progress
sftp host                                # interactive
```

## Harden `sshd`

The `sshd_config` baseline (root login, password auth, `AllowGroups`,
`MaxAuthTries`, fail2ban, bastion pattern) lives in
[ssh-hardening-reference.md](ssh-hardening-reference.md). Always `sshd -t`
before `systemctl reload ssh`, and keep a second session open while testing.

## Debugging
```bash
ssh -v host            # -vv / -vvv for more; shows which key is offered, why auth fails
ssh -o IdentitiesOnly=yes -i ~/.ssh/thatkey host
ssh-keyscan host >> ~/.ssh/known_hosts       # pre-seed host key (verify the fingerprint!)
ssh -o StrictHostKeyChecking=accept-new host # first connect only
```
"Permission denied (publickey)" → wrong key offered, key not in `authorized_keys`,
or `authorized_keys`/`.ssh` perms too open (must be `700`/`600`, owned by the user).
