# A backup design that actually restores

Target: **3** copies, **2** media/locations, **1** off-site — and every layer
tested by an actual restore, not by hoping.

## Layers

| Layer | What | How |
|---|---|---|
| App-consistent data | DB dumps, not raw files | `pg_dumpall`, `mysqldump`, `sqlite3 .backup`, app export APIs |
| Config | `/etc` subset, compose files, provisioning scripts | a **private git repo** (or a `git bundle` inside the encrypted archive) — every change is a revertible diff |
| Bulk data | media, documents, home dirs | `rsync -a --delete` or ZFS `send`/`syncoid` to a second box |
| Off-site | all of the above | a second physical location, or object storage; **encrypted before it leaves** |

## Encrypt before it leaves the host

```bash
# encrypt a stream to a recipient's public key (age):
pg_dumpall -U postgres | gzip | age -r age1... -o dump.sql.gz.age
# decrypt (needs the private key, kept OFFLINE — password manager / paper):
age -d -i key.txt dump.sql.gz.age | gunzip | psql -U postgres
```
Rule: the machine being backed up holds only the **public** key. The private key
lives somewhere the backup target can't reach. Lose it → the archives are noise.

## `--delete` is a footgun

A `--delete` mirror propagates deletions and bad writes to the copy on the next
run. Mitigations, in order of preference:
1. **Snapshots** on the target (ZFS / Btrfs) with a retention policy — real
   point-in-time recovery.
2. `rsync --backup --backup-dir=.trash/$(date +%F)` + a cron that prunes `.trash`
   after N days.
3. At minimum, a delay between "source changed" and "mirror runs" so a mistake
   is noticed first.

## Config history rides along

If you don't want a hosted git repo for `/etc`:
```bash
git -C /etc/myconfig bundle create - --all | age -r age1... -o config.bundle.age
# restore:  age -d -i key.txt config.bundle.age > c.bundle && git clone c.bundle
```
Put that line in the same script that makes the nightly encrypted archive.

## Verify (the part everyone skips)

- **Weekly**: do the archives exist, are they younger than N hours, do they pass
  an integrity check (`gzip -t`, `age -d | head -c1`, `sha256sum -c`)? Automate
  it — see [../scripts/backup-verify.sh](../scripts/backup-verify.sh).
- **Quarterly**: restore the DB into a scratch instance and run a query.
  Restore a hypervisor image to a throwaway VMID and boot it. A backup you have
  never restored is a hypothesis.

## Retention

Keep more recent, fewer old: e.g. 7 daily, 4 weekly, 6 monthly. Prune by count,
newest-first:
```bash
ls -1t /backups/db/*.age | tail -n +$((KEEP+1)) | xargs -r rm -f
```
