# Config-as-Code Repo Hygiene

Keeping server config, Compose stacks, or IaC in git is worth doing, but a
config repo leaks secrets more easily than an application repo — one careless
`git add -A` and an API token is in the history forever. This is a practical
checklist for keeping one clean.

## Secrets never go in git

Real values live in `.env` files (or a secret manager); the repo holds only a
template.

```gitignore
# .gitignore
.env
**/.env
*.env
!*.env.example        # but DO track the templates
*.key
*.pem
id_ed25519*
!*.pub
secrets.yml
```

Commit a `.env.example` next to every stack that lists the variable *names*
with blank or default values. Generate and check these automatically with
[compose-env-example.sh](../scripts/compose-env-example.sh):

```bash
./compose-env-example.sh          # write / update every .env.example
./compose-env-example.sh -c       # CI: fail if any is missing or stale
```

## Scan at commit time

Install a [gitleaks](https://github.com/gitleaks/gitleaks) pre-commit hook so
a secret can't be committed in the first place.

`.pre-commit-config.yaml`:

```yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.21.2
    hooks:
      - id: gitleaks
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-merge-conflict
  - repo: local
    hooks:
      - id: no-real-env
        name: block committing a real .env
        language: fail
        entry: "A real .env is staged. Commit only .env.example."
        files: '(^|/)\.env(\.[^/]*)?$'
        exclude: '\.env\.example$'
```

```bash
pipx install pre-commit
pre-commit install
pre-commit run --all-files      # scan what's already there
```

Optionally add a `.gitleaks.toml` that `extend`s the default rules and
allowlists your own placeholder conventions (`${VAR}`, `CHANGE-ME`,
`<REDACTED>`), so real findings aren't buried in noise.

## Validate before deploy

Broken YAML or a missing service reference should fail in CI, not on the host.

```bash
./compose-validate.sh -d .      # docker compose config on every stack
```

`docker compose config` only *warns* on unset `${VAR}` (expected — real values
aren't in the repo), so it's safe to run without the secrets present.

## Redact captured state

If the repo also stores *snapshots* of live config (firewall rules, DNS zones,
dashboards, `tailscale` state), pipe every export through a redactor before it
lands. A conservative pattern: replace the value of any JSON/YAML key whose
name matches `/(?i)(key|secret|token|password|auth)/`, plus anything that
looks like a private key block or a known token prefix. Over-redact — a
snapshot rarely needs the actual secret to be useful for diffing.
See [grafana-dashboard-export.sh](../scripts/grafana-dashboard-export.sh) and
[tailscale-export.sh](../scripts/tailscale-export.sh) for worked examples.

## CI outline

```yaml
# .github/workflows/validate.yml
on: [push, pull_request]
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: gitleaks/gitleaks-action@v2
      - run: ./compose-validate.sh -d .
      - run: ./compose-env-example.sh -c
```

## If a secret does get committed

1. **Rotate it first.** It's public the moment it's pushed — treat it as burned.
2. Then scrub history (`git filter-repo --replace-text`, or a fresh `git init`
   for a small repo) and force-push.
3. Add a `.gitleaks.toml` rule or `.gitignore` entry so it can't recur.
