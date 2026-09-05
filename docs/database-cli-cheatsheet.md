# Database CLI Cheatsheet

Day-to-day `psql`/`mysql`/`redis-cli` commands for poking at a running
database — connecting, looking around, and running one-off queries. For
the backup/restore workflow itself, see
[database-backup-restore-guide.md](database-backup-restore-guide.md) and
[stack-db-dump.sh](../scripts/stack-db-dump.sh). Most databases in a
Compose-based homelab run inside a container, so most of these are prefixed
with `docker exec` in practice.

## Connecting

```bash
psql -h localhost -U app_user -d app_db                     # native
docker exec -it <container> psql -U app_user -d app_db      # in a container

mysql -h localhost -u app_user -p app_db
docker exec -it <container> mysql -u app_user -p app_db

redis-cli -h localhost -p 6379
docker exec -it <container> redis-cli
```
Passing `-p`/a password on the command line puts it in shell history and
`ps` output — prefer a `.pgpass`/`.my.cnf` file, an env var the client
reads itself (`MYSQL_PWD`, `PGPASSWORD`), or an interactive prompt.

## PostgreSQL (psql)

```
\l                          -- list databases
\c dbname                   -- connect to a different database
\dt                         -- list tables in the current schema
\d tablename                -- describe a table (columns, indexes, constraints)
\du                         -- list roles/users and their attributes
\x                          -- toggle expanded output (one column per line)
\timing                     -- show query execution time
\q                          -- quit
```
```sql
SELECT pid, usename, state, query, now() - query_start AS runtime
  FROM pg_stat_activity WHERE state != 'idle' ORDER BY runtime DESC;  -- running queries
SELECT pg_terminate_backend(<pid>);                                    -- kill a query/session
SELECT pg_size_pretty(pg_database_size('app_db'));                     -- database size
```

## MySQL / MariaDB

```sql
SHOW DATABASES;
USE app_db;
SHOW TABLES;
DESCRIBE tablename;
SHOW GRANTS FOR 'app_user'@'%';
SHOW PROCESSLIST;                          -- running queries/connections
KILL <id>;                                 -- kill a connection (from SHOW PROCESSLIST)
SELECT table_schema, ROUND(SUM(data_length+index_length)/1024/1024,1) AS mb
  FROM information_schema.tables GROUP BY table_schema;   -- size per database
```

## Redis

```bash
redis-cli PING                    # liveness check
redis-cli INFO server             # version, uptime, config summary
redis-cli DBSIZE                  # number of keys in the current DB
redis-cli KEYS "session:*"        # find keys by pattern — avoid on a busy prod instance
redis-cli --scan --pattern "session:*"   # same idea, non-blocking (safe under load)
redis-cli TTL <key>                # remaining time-to-live, -1 = no expiry, -2 = missing
redis-cli MONITOR                  # live stream of every command (very noisy, debug only)
redis-cli CONFIG GET maxmemory     # check a config value
redis-cli SAVE                     # force an RDB snapshot now
```
`KEYS` scans the entire keyspace and blocks the single-threaded server
while it runs — fine on a small dev instance, a real problem on anything
with meaningful traffic. Use `--scan` instead once the dataset is
non-trivial.

## SQLite

```bash
sqlite3 app.db ".tables"                       # list tables
sqlite3 app.db ".schema tablename"             # show a table's schema
sqlite3 app.db "SELECT * FROM users LIMIT 5;"  # ad-hoc query
sqlite3 app.db ".backup /tmp/app-backup.db"    # safe online backup (vs. copying the file)
```
Copying a SQLite file while the application is writing to it can grab a
torn/inconsistent snapshot — `.backup` (or the `VACUUM INTO` SQL command)
takes a consistent copy through SQLite's own API instead.

## Notes

- Read replicas/standbys aside, running an unbounded `SELECT` or `KEYS`
  against production during business hours is how a "just checking
  something" session becomes an incident — reach for `LIMIT`, `--scan`,
  or a replica first.
- `\timing` (psql) / query profiling in general is worth turning on before
  investigating "this is slow" reports — confirm the specific query is
  actually the slow part before optimizing anything.
- Container database credentials in this homelab are read from the
  container's own environment rather than passed on a command line — see
  [stack-db-dump.sh](../scripts/stack-db-dump.sh) for the pattern.
