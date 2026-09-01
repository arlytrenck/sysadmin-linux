# NAS hardening audit

A walk-through for a consumer/prosumer NAS (Synology, QNAP, TrueNAS, or a
roll-your-own). Do it once properly, then re-check quarterly. Items are grouped
by where you'll find them in a typical NAS UI.

## Storage & data integrity
- [ ] Pool/volume status **Healthy**. Note the **RAID level** — if it's RAID0 /
      striped / a JBOD span, you have **zero** redundancy: one disk lost = all
      data on that pool lost. Decide deliberately whether that's acceptable for
      what's on it.
- [ ] **SMART**: run an extended test on every disk; check reallocated / pending
      / uncorrectable sector counts and power-on hours. Plan replacement for
      disks past ~5 years or with rising reallocations.
- [ ] **Scrub / data-integrity check scheduled** (monthly) and its last run
      *passed*. A disabled or perpetually "paused" scrub is a silent risk.
- [ ] Mixed-vendor, mixed-age, mixed-size disks in one redundancy group is fine
      functionally but plan capacity around the **smallest** member.
- [ ] Any non-NAS-rated (desktop) drives in a 24/7 array → schedule replacement.

## Snapshots (a mirror is not a snapshot)
- [ ] Filesystem snapshots enabled on the important shares (e.g. hourly keep 24,
      daily keep 7) — this is your real point-in-time recovery.
- [ ] Understand that an `rsync --delete` mirror to a second NAS propagates a bad
      write on the next run. Snapshots on the *target* fix this; a time-limited
      `.trash` dir is the weak fallback.

## OS / firmware
- [ ] On the current stable release; security updates applied.
- [ ] Update policy = **download + notify**, not auto-install-and-reboot (you
      want to choose the window, especially on beta/preview tracks).

## Accounts & access
- [ ] Default `admin`/`administrator` account **disabled**; a differently-named
      admin account in use.
- [ ] **2FA/MFA** on every admin account (ideally enforced org-wide).
- [ ] **Auto-block** / brute-force lockout on (e.g. 10 fails / 5 min).
- [ ] Per-account lockout / "account protection" on if the platform has it.
- [ ] The account used for network mounts is **least-privilege** (access to only
      the shares it needs), not an admin account. Rotate its password; store it
      `chmod 600`.

## Network exposure
- [ ] Management UI **not** reachable from untrusted networks — firewall it to a
      management VLAN / specific hosts, or only over VPN. If the built-in
      firewall is "enabled" it must actually have rules; enabled-with-no-rules
      often means default-allow (a no-op).
- [ ] Disable unused file protocols (AFP, FTP, Telnet, WebDAV, SNMP if not
      scraped). Keep only what a client actually uses (usually SMB **or** NFS).
- [ ] NFS exports IP-restricted; SMB min protocol SMB2 (SMB1 off); consider
      forcing SMB transfer encryption + signing on sensitive shares.
- [ ] SSH off, or on a non-default port with key-only auth, or firewalled.

## Power & alerting
- [ ] On a **UPS** with safe-shutdown configured (USB or networked). A power
      event mid-write on a no-redundancy array is the nightmare case.
- [ ] **Notifications configured and tested** — email *and* push — for: drive
      failure, volume degraded/crashed, scrub result, SMART warning, UPS events,
      update available, abnormal login. A NAS that can't tell you it's dying is
      a single point of silent failure.

## Recycle bin
- [ ] Enabled per share with a sane retention; not just relied on as "undo".
