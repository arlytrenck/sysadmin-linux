# Backup Restore Drill

A backup you have never restored is a guess. This is a short, repeatable
exercise to turn that guess into a fact. Run it quarterly and after any change
to what or how you back up.

Related: [backup-dr-testing-runbook.md](backup-dr-testing-runbook.md) (the
broader DR test), [database-backup-restore-guide.md](database-backup-restore-guide.md).

## Before you start

- Restore into a **scratch location**, never over live data.
- Have the decryption key / passphrase on hand and confirm you can read it.
- Note the time — measuring how long a restore takes is half the point.

## 1. Inventory what's actually protected

For each service, write down one line: what's the stateful part, how is it
captured, where does the copy land, how often, how many kept.

```bash
# what's stateful under a stack of compose projects
for d in */ ; do
  echo "== $d"
  grep -E 'volumes:|/.*:/' "$d"/*compose*.y*ml 2>/dev/null | grep -v ':ro'
done
```

Anything stateful with no line is a gap. Common misses: a named volume that
`rsync` never sees, a container-internal SQLite file, Redis with no
persistence, `uploads/` outside the volume you back up.

## 2. Verify the artifacts exist and are readable

```bash
# recent? non-empty? checksums match?
ls -lt backups/ | head
( cd backups && sha256sum -c SHA256SUMS 2>/dev/null | grep -v ': OK$' )

# encrypted artifact actually decrypts
age -d -i ~/keys/age-identity.txt backups/postgres-latest.sql.gz.age | zcat | head -5
```

If a `.age` file won't decrypt with the key you have, the backup is already
worthless — fix that first.

## 3. Restore a database

```bash
mkdir -p /tmp/restore && cd /tmp/restore

# spin a throwaway instance of the same engine/version
docker run -d --name restore-pg -e POSTGRES_PASSWORD=x postgres:16
sleep 5

age -d -i ~/keys/age-identity.txt /path/postgres-latest.sql.gz.age \
  | zcat | docker exec -i restore-pg psql -U postgres

# sanity: row counts, latest timestamps in a few key tables
docker exec restore-pg psql -U postgres -c "\dt+" -c "SELECT max(created_at) FROM <table>;"
docker rm -f restore-pg
```

## 4. Restore an app's files

```bash
mkdir -p /tmp/restore/app
tar -xzf /path/app-data-latest.tar.gz -C /tmp/restore/app     # or: age -d ... | tar -xz
diff -qr /tmp/restore/app/<subset> /live/path/<subset> | head    # spot differences
```

## 5. Record the result

| date | artifact | age of copy | decrypt OK | restore time | data current to | notes |
|---|---|---|---|---|---|---|
| | | | | | | |

If the restore failed, the copy was stale, or the RPO (how much data you'd
lose) is worse than you assumed — that's a finding. Fix it and re-run this
section, don't wait for next quarter.

## 6. Full-box dry run (annually)

On a spare machine or VM: install the OS, restore `/etc` + `/scripts` from
the config snapshot, `git clone` the config repo, populate `.env` from the
password manager, `docker compose up -d`, restore the databases and app data,
and time the whole thing end to end. That number is your real recovery time.
