# Database Backup & Restore Guide (MySQL/MariaDB & PostgreSQL)

A focused guide for the two most common self-hosted database engines.
Pairs with [backup-dr-testing-runbook.md](backup-dr-testing-runbook.md),
which covers *testing* that these backups actually restore — do that
periodically, not just once.

## MySQL / MariaDB

### Logical backup (portable, human-inspectable, slower to restore)

```bash
# Single database
mysqldump --single-transaction --routines --triggers --events \
  -u backup_user -p mydb > mydb-$(date +%F).sql

# All databases
mysqldump --single-transaction --all-databases \
  -u backup_user -p > all-$(date +%F).sql
```

`--single-transaction` avoids locking InnoDB tables during the dump; it
does not help for MyISAM tables, which will still be briefly locked.

### Restore

```bash
mysql -u root -p mydb < mydb-2025-01-01.sql
```

### Physical backup (faster restore, larger, engine-specific)

For larger databases, a hot-copy tool like `mariabackup` or Percona
`xtrabackup` copies the underlying InnoDB files directly and restores
much faster than replaying a logical dump. Worth adopting once
`mysqldump` restore time starts exceeding your RTO.

### Verifying a MySQL backup without a full restore

```bash
# Confirm the dump is well-formed SQL and references expected tables
grep -c '^INSERT INTO' mydb-2025-01-01.sql
grep '^-- Dump completed' mydb-2025-01-01.sql   # mysqldump writes this on success
```

Neither check proves the backup restores cleanly — only a real restore
test does that (see the DR runbook) — but they catch a truncated or
failed dump early.

## PostgreSQL

### Logical backup

```bash
# Single database, custom format (compressed, supports parallel restore)
pg_dump -U backup_user -Fc mydb > mydb-$(date +%F).dump

# All databases + roles
pg_dumpall -U backup_user > all-$(date +%F).sql
```

### Restore

```bash
# Custom-format dump into a fresh database
createdb mydb_restore
pg_restore -U postgres -d mydb_restore mydb-2025-01-01.dump

# Plain SQL dump (pg_dumpall output)
psql -U postgres < all-2025-01-01.sql
```

### Physical backup (base backup + WAL archiving)

For point-in-time recovery, not just point-in-time-of-last-dump:

```bash
pg_basebackup -U replication_user -D /backup/base -Fp -Xs -P
```

Combined with continuous WAL archiving, this lets you restore to any
moment, not just the last dump time — the right approach once your RPO
is measured in minutes rather than "since last night's dump".

### Verifying a PostgreSQL backup without a full restore

```bash
# Custom-format dumps carry an internal TOC — list it without restoring
pg_restore --list mydb-2025-01-01.dump | head
```

A dump that `pg_restore --list` can't parse is corrupt; catch that at
backup time rather than during an incident.

## General practices for both

- **Encrypt backups at rest**, especially if they leave the host
  (`gpg --symmetric` or your storage layer's native encryption).
- **Keep credentials for the backup user separate and minimally
  privileged** — a backup account needs read access, not full admin.
- **Store backups off the source host.** A backup that lives only on the
  server it backs up is lost in the same failure that takes the server.
- **Automate + alert on failure**, not just on success — a silently
  failing nightly cron job is worse than no backup, because it creates
  false confidence. `update-and-patch.sh`-style non-zero exit codes wired
  into a webhook (see
  [monitoring-alerting-guide.md](monitoring-alerting-guide.md)) close
  that gap cheaply.
- **Retain more than one generation.** A single overwritten "latest"
  backup doesn't protect against corruption that's already been backed
  up before anyone noticed.
