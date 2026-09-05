# Text Processing Cheatsheet

`grep`/`sed`/`awk`/`jq` cover the vast majority of "find this in a log" and
"reshape this output" tasks without reaching for a scripting language.
Reach for `awk` once a pipeline needs more than one field; reach for `jq`
the moment the input is JSON — parsing JSON with `grep`/`sed` is a trap.

## grep

```bash
grep -R "ERROR" /var/log/app/               # recursive
grep -i "error" file.log                    # case-insensitive
grep -v "DEBUG" file.log                    # invert match — everything except
grep -c "ERROR" file.log                    # count matching lines
grep -n "ERROR" file.log                    # show line numbers
grep -E "ERROR|WARN" file.log                # extended regex, alternation
grep -A3 -B1 "Traceback" file.log            # 3 lines after, 1 before, a match
grep -oP '(?<=user=)\S+' file.log            # Perl regex, print only the capture
grep -l "ERROR" *.log                        # just the filenames that match
zgrep "ERROR" file.log.gz                    # grep inside a gzip file directly
```

## sed

```bash
sed 's/foo/bar/' file            # first match per line, prints to stdout
sed 's/foo/bar/g' file           # every match per line
sed -i 's/foo/bar/g' file        # edit in place (no backup)
sed -i.bak 's/foo/bar/g' file    # edit in place, keep file.bak
sed -n '10,20p' file             # print only lines 10-20
sed '/^#/d' file                 # delete comment lines
sed -n '/START/,/END/p' file     # print between two markers, inclusive
```
`sed -i` on a symlink rewrites the target file's content in place, but on
some filesystems it swaps in a new inode — don't rely on it preserving a
bind mount or hardlink identity.

## awk

```bash
awk '{print $1, $3}' file                       # 1st and 3rd whitespace-delimited fields
awk -F: '{print $1}' /etc/passwd                 # custom field separator
awk '$3 > 90 {print $1, $3}' usage.txt           # filter rows by a numeric field
awk '{sum += $1} END {print sum}' file           # sum a column
awk 'NR==1 || /pattern/' file                    # keep the header line plus matches
awk '{print NR": "$0}' file                      # prefix each line with its line number
awk 'BEGIN{OFS=","} {print $1,$2}' file          # change the output separator
```
awk field splitting on whitespace treats runs of spaces/tabs as one
separator — good for `df`/`ps` output, wrong for anything that pads fields
with fixed-width spaces.

## jq (JSON)

```bash
curl -s api/status | jq .                            # pretty-print
jq '.items[] | .name' data.json                       # iterate an array, pull a field
jq -r '.items[].name' data.json                        # -r: raw strings, no quotes
jq '.items | length' data.json                         # array length
jq '.items[] | select(.status=="failed")' data.json    # filter objects
jq '[.items[].name]' data.json                         # collect into a new array
jq -c '.' data.json                                    # compact (one object per line)
jq '.a.b.c // "default"' data.json                      # fallback when a path is null/missing
docker inspect <id> | jq '.[0].Config.Env'             # pull one field out of docker inspect
```

## sort / uniq / cut / column

```bash
sort -n file                      # numeric sort
sort -k2,2 -t: file                # sort by the 2nd colon-delimited field
sort -h file                       # human-readable sizes (1K, 2M, 3G) sort correctly
uniq -c file                      # count consecutive duplicate lines (sort first!)
sort file | uniq -c | sort -rn     # classic "top N occurrences" pipeline
cut -d: -f1,3 /etc/passwd          # fields 1 and 3, colon-delimited
column -t -s: /etc/passwd          # align delimited columns for reading
```
`uniq` only collapses *adjacent* duplicates — always `sort` first unless the
input is already grouped.

## Quick combinations worth remembering

```bash
# top 10 IPs hitting an access log
awk '{print $1}' access.log | sort | uniq -c | sort -rn | head -10

# tail a log and highlight a pattern live
tail -f app.log | grep --line-buffered -E "ERROR|WARN"

# find the largest N files under a path
find . -type f -printf '%s %p\n' | sort -rn | head -20

# replace a value across every file under a directory
grep -rl "old-hostname" /etc/ | xargs -r sed -i 's/old-hostname/new-hostname/g'
```

## Notes

- `grep --line-buffered` matters the moment grep sits in a pipe with `tail
  -f`/`journalctl -f` on the input side — without it, output can sit in a
  buffer and never appear until enough of it accumulates.
- Prefer `awk`/`jq` over chained `cut`/`sed` once a pipeline needs a
  computed value or a conditional — chained one-liners that "sort of work"
  on today's log format are the ones that silently break on tomorrow's.
- `LC_ALL=C` before `sort`/`grep` on large files gives a meaningful speedup
  and byte-order sorting instead of locale-aware collation, which is
  usually what you actually want for logs.
