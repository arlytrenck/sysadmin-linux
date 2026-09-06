# rsync Cheatsheet

Fast, resumable, delta-based copying — locally, over SSH, and to/from network
mounts. The focus here is the flags that matter and the ones that will bite
you (`--delete`, trailing slashes, `--size-only` on CIFS). See also
[backup-3-2-1-runbook.md](backup-3-2-1-runbook.md) and
[backup-verify.sh](../scripts/backup-verify.sh).

## The trailing slash rule (the #1 mistake)

```bash
rsync -a src/  dst/     # copy the CONTENTS of src into dst
rsync -a src   dst/     # copy the DIRECTORY src, creating dst/src/
```

A slash on the **source** means "the contents of". No slash means "this
directory itself". The destination slash barely matters. Get this wrong with
`--delete` and you either nest a directory or wipe the level above.

## Everyday invocations

```bash
rsync -av  src/ dst/                       # archive + verbose
rsync -avz src/ user@host:/dst/            # over SSH, compressed
rsync -av --dry-run --delete src/ dst/     # SHOW what would change/delete — always do this first
rsync -aP  src/ dst/                       # --partial --progress (resumable, per-file progress)
rsync -a --info=progress2 src/ dst/        # single overall progress bar (rsync 3.1+)
```

`-a` (archive) = `-rlptgoD`: recurse, symlinks, perms, times, group, owner,
devices/specials. It does **not** include `-H` (hardlinks), `-A` (ACLs),
`-X` (xattrs), or `-S` (sparse) — add those explicitly if you need them.

## Flags worth knowing

| Flag | Effect |
|------|--------|
| `-n` / `--dry-run` | change nothing, print what would happen |
| `-c` / `--checksum` | compare by checksum, not size+mtime (slow, thorough) |
| `--size-only` | compare by size alone — skip files whose size matches |
| `--ignore-times` | copy every file regardless (re-sync after a bad run) |
| `-u` / `--update` | skip files that are newer on the destination |
| `--delete` | delete dest files that no longer exist in source |
| `--delete-delay` / `--delete-after` | delete at the end, not as-you-go |
| `--max-delete=N` | abort if more than N deletions would happen (circuit breaker) |
| `--backup --backup-dir=DIR` | move overwritten/deleted files into DIR instead of losing them |
| `--partial-dir=.rsync-tmp` | keep partial transfers in a subdir, not the target path |
| `--bwlimit=10M` | throttle bandwidth |
| `--exclude-from=FILE` / `--exclude=PAT` | skip matching paths |
| `--files-from=FILE` | copy exactly this list |
| `-x` / `--one-file-system` | don't cross mount points |
| `--numeric-ids` | don't map uid/gid by name (right for cross-host/backup) |
| `--inplace` | write into the existing file (for huge files / VM images; breaks atomicity) |
| `--link-dest=DIR` | unchanged files become hardlinks to DIR (snapshot-style backups) |
| `--itemize-changes` / `-i` | one line per change, with a reason code |

## `--delete` safely

`--delete` makes the destination an exact mirror. A bad source (empty,
half-mounted, wrong path) becomes mass deletion.

```bash
rsync -a --dry-run --delete src/ dst/ | tail
```

Guard rails for an automated mirror job:

```bash
# refuse to run if the source isn't really mounted / populated
mountpoint -q /mnt/source || exit 1
[ -e /mnt/source/.sync-sentinel ] || exit 1        # a file you know must exist

rsync -a --delete \
  --max-delete=10000 \                             # abort on suspicious mass delete
  --backup --backup-dir=/mnt/dest/.trash/$(date +%F_%H%M%S) \   # recoverable for N days
  --partial-dir=.rsync-partial \
  --exclude-from=/etc/backup/excludes.txt \
  /mnt/source/ /mnt/dest/
rc=$?
# rc 25 = --max-delete hit. Investigate the pending deletions before overriding.
```

Then prune the backup-dir on a schedule (`find /mnt/dest/.trash -mtime +14
-delete`).

## The itemize output, decoded

`rsync -i` prints e.g. `>f.st......`:

```
< or >  transfer direction (recv / send)   c  local change/creation
f       file  (d dir, L symlink)           .  no change, attrs match
 c      checksum differs (or new)          *  message (e.g. deleting)
  s     size differs
   t    mtime differs
    p   perms   o owner   g group   a acl   x xattr
```

`>f+++++++++` = brand new file. `>f..t......` = same content, mtime pushed.
`*deleting` = removed by `--delete`.

## Over SSH

```bash
rsync -avz -e 'ssh -p 2222 -i ~/.ssh/id_ed25519' src/ user@host:/dst/
rsync -av --rsync-path='sudo rsync' src/ user@host:/dst/     # write as root on the far side
```

- Compression (`-z`) helps on slow links, hurts on fast LAN / already-
  compressed data (video, archives) — measure.
- `-e` sets the remote shell; put host-specific options in `~/.ssh/config`
  instead and just `rsync -av src/ host:/dst/`.

## Network mounts (CIFS/SMB, NFS) — the mtime trap

CIFS destinations often **cannot preserve mtime** (`utime()` on the share is
ignored). With default size+mtime comparison, rsync then re-copies unchanged
files forever, or an `-u`/`-t` combination masks real drift.

- Use `--size-only` when the destination can't hold mtimes, so comparison is
  size-based and stable. Accept that a same-size content change won't be
  detected (rare for most data; use `-c` for a periodic deep pass).
- `--modify-window=2` tolerates FAT/SMB 2-second timestamp granularity.
- CIFS `soft` mounts can truncate a large file on a network blip — pair with
  `--partial-dir` and verify big files afterward (`sha256sum`, `gzip -t`).
- Symlinks fail on CIFS (`ln: Operation not supported`) — rsync `-l` will
  error; use `-L` (copy the target) or `--munge-links`.

## Snapshot-style backups with `--link-dest`

```bash
DEST=/backup/$(date +%F_%H%M%S)
rsync -a --delete --link-dest=/backup/latest / "$DEST/"
ln -sfn "$DEST" /backup/latest
```

Unchanged files are hardlinks to the previous run — each snapshot costs only
the delta, but browses as a full tree. (Dedicated tools — restic, borg,
ZFS/btrfs snapshots — do this better; `--link-dest` is the no-extra-software
option.)

## Exit codes

`0` ok · `23` partial transfer (some files failed — perms, vanished) · `24`
source files vanished during run (usually benign) · `25` `--max-delete`
limit hit · `30`/`35` timeout. In scripts, treat `24` as a warning and
anything else non-zero as failure.
