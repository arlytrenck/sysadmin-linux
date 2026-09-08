# Firewall Cheatsheet

Inspecting and changing host packet filtering across the three front-ends
you'll actually meet: `nftables`, `ufw`, `firewalld`. Plus the legacy
`iptables` view and the Docker interaction that surprises everyone. See also
[firewall-rules-dump.sh](../scripts/firewall-rules-dump.sh) and
[server-hardening-checklist.md](server-hardening-checklist.md).

## First: what's actually running?

```bash
sudo nft list ruleset | head              # nftables (modern default)
sudo iptables -S; sudo iptables -L -n -v  # iptables view (may be nft under the hood)
sudo ufw status verbose                   # Ubuntu's front-end (wraps nft/iptables)
sudo firewall-cmd --state                 # RHEL/Fedora front-end
systemctl is-active nftables ufw firewalld
```

Pick **one** front-end and stick to it. Running `ufw` and raw `nft` rules and
`firewalld` at once is how you get rules that silently don't apply.

`iptables` on a modern distro is usually `iptables-nft`, a translation
shim. `iptables -S` shows you a compatible view; `nft list ruleset` shows the
real thing.

## nftables

```bash
sudo nft list ruleset                      # everything
sudo nft list table inet filter            # one table
sudo nft -a list chain inet filter input   # with handles (needed to delete a rule)

# add / delete
sudo nft add rule inet filter input tcp dport 22 accept
sudo nft delete rule inet filter input handle 7

# persist (Debian/Ubuntu): edit and reload
sudoedit /etc/nftables.conf
sudo nft -f /etc/nftables.conf
sudo systemctl enable --now nftables
```

Minimal sane `/etc/nftables.conf`:

```nft
#!/usr/sbin/nft -f
flush ruleset
table inet filter {
  chain input {
    type filter hook input priority 0; policy drop;
    ct state established,related accept
    iif lo accept
    ct state invalid drop
    ip protocol icmp accept
    ip6 nexthdr ipv6-icmp accept
    tcp dport 22 accept
    # tcp dport { 80, 443 } accept
  }
  chain forward { type filter hook forward priority 0; policy drop; }
  chain output  { type filter hook output priority 0; policy accept; }
}
```

Test remote-access changes behind a safety net so a mistake doesn't lock you
out:

```bash
sudo nft -f /etc/nftables.conf && sleep 20 && echo ok || sudo nft flush ruleset
# or: `at now + 2 minutes <<< 'nft flush ruleset'` before applying, cancel with atrm if ok
```

## ufw (Ubuntu)

```bash
sudo ufw status numbered
sudo ufw allow 22/tcp
sudo ufw allow from 10.0.0.0/24 to any port 5432 proto tcp
sudo ufw limit 22/tcp                    # rate-limit (brute-force slow-down)
sudo ufw delete 3                        # by line number from `status numbered`
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw enable                          # persists across reboot
sudo ufw reload
sudo ufw --dry-run allow 80/tcp          # preview the generated rules
tail -f /var/log/ufw.log                 # blocked packets (with logging on)
```

## firewalld (RHEL/Fedora)

```bash
sudo firewall-cmd --get-active-zones
sudo firewall-cmd --list-all                                # running config, default zone
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --permanent --zone=internal --add-source=10.0.0.0/24
sudo firewall-cmd --reload                                  # apply permanent
sudo firewall-cmd --runtime-to-permanent                    # keep current runtime rules
```

`--permanent` changes need `--reload`; without `--permanent` they're lost on
reload/reboot.

## Docker bypasses your host firewall

**This catches everyone.** When you publish a port (`-p 8080:80` /
`ports:` in compose), Docker inserts its own rules in the `DOCKER` /
`DOCKER-USER` chains that are evaluated **before** `ufw`/`firewalld` zone
rules. `ufw deny 8080` does **not** block a Docker-published `8080`.

Mitigations, best first:

1. **Bind to a specific address, not `0.0.0.0`:**
   `-p 127.0.0.1:8080:80` (proxy-only) or `-p 10.0.0.5:8080:80` (LAN-only).
   This is the real fix. See
   [container-security-guide.md](container-security-guide.md).
2. **Filter in `DOCKER-USER`** (evaluated before `DOCKER`, survives restarts):
   ```bash
   sudo iptables -I DOCKER-USER -i eth0 ! -s 10.0.0.0/24 -p tcp --dport 8080 -j DROP
   ```
3. **`ufw-docker`**: a helper that adds a `DOCKER-USER` block plus
   per-container allow rules driven by `ufw route allow`. Treat adopting it
   as a small project, not a toggle; test every published port after.
4. Set `"iptables": false` in `/etc/docker/daemon.json` only if you're
   prepared to write all the NAT/forward rules yourself, usually not worth it.

Verify what's *actually* reachable rather than trusting the firewall config:

```bash
sudo ss -tulpn | grep -v '127.0.0.1\|::1'    # anything listening on a routable address
sudo nmap -sT -p- <this-host-ip>             # from another machine
```

## Quick "is this port open" checks

```bash
sudo ss -tulpn sport = :443            # is anything listening locally
nc -zv host 443                        # from a client: can I reach it
curl -sS -o /dev/null -w '%{http_code}\n' https://host/   # does it answer
timeout 3 bash -c '</dev/tcp/host/443' && echo open || echo closed   # no tools needed
```

## Logging dropped packets

```nft
# in the input chain, before the final drop:
log prefix "nft-drop: " flags all counter drop
```
```bash
sudo ufw logging medium
journalctl -k | grep -E 'nft-drop|UFW BLOCK|IN=.*DPT='
```

Turn verbose logging off again once you've diagnosed the issue. It's noisy
and fills the journal.
