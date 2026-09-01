# Git for Ops

Config in git, secrets out of git. The value is the **diff** — every change to a
compose file, a Caddyfile, `/etc` is something you can see and revert.

## Recover from mistakes
```bash
git reflog                       # every HEAD you've had — your undo history
git reset --hard HEAD@{2}        # jump back to a reflog entry
git restore --source=HEAD~1 path # one file from a past commit, keep the rest
git revert <sha>                 # new commit that undoes <sha> (safe on shared branches)
git checkout -                   # previous branch
git stash ; git stash pop        # park uncommitted work
```
Deleted a branch? `git reflog` still has the tip sha → `git branch name <sha>`.

## Find when/where something broke
```bash
git log -p -- path/to/file        # history of one file, with diffs
git log -S 'someString' --oneline # commits that added/removed that string
git blame -L 40,60 file           # who last touched these lines
git bisect start ; git bisect bad ; git bisect good <sha>
  # git checks out the midpoint; you test, then: git bisect good|bad ; repeat
git bisect run ./test.sh          # automate it
```

## Before making a repo public
```bash
git log --all -p | grep -nEi 'api[_-]?key|secret|token|password|BEGIN .*PRIVATE'
git ls-files | xargs grep -nEi 'password|secret' 2>/dev/null
```
If a secret is in **history** (not just the current tree), a plain delete isn't
enough — either rewrite history (`git filter-repo --path X --invert-paths`) or,
simpler for a young repo, `rm -rf .git && git init` and one clean commit. Then
**rotate the secret regardless** — assume it leaked.

## Config-repo hygiene
```bash
# a bare repo + worktree so /etc isn't littered with .git:
git init --bare ~/.etc.git
alias etc='git --git-dir=$HOME/.etc.git --work-tree=/etc'
etc add /etc/nginx ; etc commit -m 'nginx tweak'
```
Or just `git init` a subdir you control and symlink from `/etc`.

## Bundles (offline transport / backup)
```bash
git bundle create repo.bundle --all      # whole history in one file
git clone repo.bundle restored           # rehydrate anywhere
```
Great for putting config history inside an encrypted backup without a server.

## Remotes / deploy keys
```bash
git remote -v
git remote set-url origin git@host:owner/repo.git
# per-repo SSH key via a host alias in ~/.ssh/config:
#   Host gh-thisrepo
#     HostName github.com
#     IdentityFile ~/.ssh/id_ed25519_thisrepo
#     IdentitiesOnly yes
# then:  git remote set-url origin git@gh-thisrepo:owner/repo.git
```
A **deploy key** is scoped to one repo — safer on a server than an account key.

## Handy
```bash
git status -sb                    # compact + ahead/behind
git commit --amend --no-edit      # fold staged changes into the last commit (unpushed only)
git clean -ndx                    # dry-run: what would be removed
git diff --cached                 # what's staged
git config --global rerere.enabled true   # remember conflict resolutions
```
