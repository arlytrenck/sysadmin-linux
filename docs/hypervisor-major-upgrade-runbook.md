# Single-node hypervisor: major-version upgrade

Generic procedure for a one-box virtualization host (Proxmox VE, XCP-ng, plain
KVM, ESXi standalone) doing a **major** OS/platform upgrade — the kind that is a
full distro `dist-upgrade` underneath. No cluster, no live-migration safety net,
so this is a scheduled maintenance window, not a live click.

## 0. Before the window

- [ ] **Guest backups exist and are verified.** Full image backup of every VM to
      storage that is *not* the boot disk, plus ideally an off-box copy. Do one
      test restore to a throwaway ID so you know the archive is good.
- [ ] **Host config captured**: network config, storage config, per-VM config,
      package selection, bootloader, `/etc` subset → a repo or a tarball off the
      box ([../scripts/system-snapshot.sh](../scripts/system-snapshot.sh)).
- [ ] **Out-of-band console** works — IPMI/iDRAC/iLO/BMC or a physical KVM. If
      the network stack breaks on reboot, the web UI is gone and you need this.
- [ ] **Free RAM / resources.** Cap host-side caches (e.g. ZFS ARC) or, better,
      **shut the guests down** for the window — the host is offline to users
      anyway, and it removes memory pressure and I/O contention from the upgrade.
- [ ] **Storage headroom** on the root/boot filesystem (the upgrade writes a lot).
- [ ] Read the vendor's official upgrade guide once, end to end.

## 1. Get fully current on the *old* major first

```bash
apt update && apt full-upgrade     # or the platform's equivalent
reboot                             # onto the newest old-major kernel   << outage 1
```
Confirm after reboot: version, storage all online/active, every guest boots and
its services come healthy. **Do not proceed if anything is off.**

## 2. Run the readiness checker

Most platforms ship one (`pve8to9`, `xe-...`, `do-release-upgrade -c`). Fix
**every** FAIL and every WARN you understand: held packages, third-party
repos/DKMS, interface names the new release renames, non-default kernel modules.

## 3. Swap the repositories to the new major, then upgrade

```bash
# point apt/yum at the new release, then:
tmux new -s upgrade                 # so a console disconnect doesn't SIGHUP it
apt dist-upgrade                    # << outage 2 — the big one, 20–60 min
```
Answer conffile prompts deliberately: **keep your version** of files you have
hand-edited (network, sshd, LVM); take the maintainer version only for platform
files you have not touched. If it stops: resolve, `apt -f install`,
`dpkg --configure -a`, continue.

## 4. Reboot + verify, in order

- [ ] version and kernel are the new major
- [ ] storage layer healthy, **no** errors (`zpool status` / equivalent); do
      **not** run irreversible one-way storage upgrades (`zpool upgrade`) yet —
      that burns your rollback path
- [ ] all storages active, `systemctl --failed` empty
- [ ] network: bridge up with the right IP; fix and reload if an iface renamed
- [ ] each guest boots → services healthy → spot-check a real user workflow
- [ ] run the package upgrade once more to catch new-major point fixes

## 5. Rollback

- Guests are safe regardless: restore the image backup to a fresh/temp ID.
- Host: boot the retained previous-major kernel from the boot menu (keep 2–3).
  If userspace is already upgraded this only half-works — which is why the
  off-box backup + OOB console + not doing one-way storage upgrades all matter.
  Worst case: reinstall the new major clean, re-import storage, restore guests,
  copy the captured config back.

## 6. After a week of stability

*Then* consider the one-way storage feature-flag upgrade and dropping the old
retained kernel.
