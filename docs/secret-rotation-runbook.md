# Secret Rotation Runbook

A repeatable procedure for rotating a credential: an API token, a database
password, an SSH key, a service account: with minimal downtime and a clean
rollback. Applies whether the secret leaked, an employee left, or it's just
overdue.

## When to rotate

- **Now, unscheduled:** the value appeared in a git history, a log, a chat
  message, a screenshot, a backup that left your control, or a terminated
  person's laptop. Assume compromise; rotate before you finish the
  post-mortem.
- **Scheduled:** long-lived tokens on a calendar (quarterly / yearly),
  after an audit finding, on a compliance requirement.

If it may have leaked, also check for damage done with the old value
(unfamiliar API calls, new resources, config changes, logins) before and
after rotating.

## Before you touch anything

1. **Inventory every place the secret is used.** A token is rarely in one
   file. Search:
   ```bash
   sudo grep -rIl 'SECRET_NAME\|<known-prefix>' /etc /opt /srv /home /root/.config 2>/dev/null
   sudo systemctl show '*' -p Environment 2>/dev/null | grep -i secret_name
   grep -rl 'SECRET_NAME' /docker /compose 2>/dev/null          # compose .env files
   ```
   Also: CI/CD variables, cloud secret managers, password manager entries,
   `~/.netrc`, `~/.aws/credentials`, cron job env, backup scripts,
   monitoring/exporters, mobile apps.
2. **Know how the consumer reloads.** Env var in a systemd unit → needs
   `daemon-reload` + service restart. A file the app watches → maybe hot.
   A container `env_file` → needs `up -d` (a plain `restart` does *not*
   re-read it).
3. **Check whether the provider allows two active credentials at once.**
   If yes, you get a zero-downtime overlap window. If no (single value per
   account), plan for a brief cutover.

## Rotation with an overlap window (preferred)

```
1. Issue a NEW credential alongside the old one (both valid).
2. Update every consumer to the new value.
3. Reload / restart each consumer; verify it works on the new value.
4. Confirm the old credential has had zero use for a full business cycle
   (check provider access logs).
5. Revoke / delete the old credential.
6. Verify nothing broke. Keep the ability to re-issue for a few days.
```

## Rotation without overlap (single-value)

```
1. Schedule a short window; note dependent services.
2. Generate the new value.
3. Update all consumers' config to the new value but DON'T restart yet.
4. In the provider, change the value.
5. Restart/reload all consumers as close together as possible.
6. Verify each; roll back (old value + restart) if a consumer won't take it.
```

## Storing the new value

- **systemd:** prefer `LoadCredential=`/`SetCredential=` or an
  `EnvironmentFile=` that's `root:root 600`, over an inline `Environment=` in
  a world-readable unit. After editing a drop-in:
  ```bash
  sudoedit /etc/systemd/system/<svc>.service.d/override.conf
  sudo systemctl daemon-reload && sudo systemctl restart <svc>
  systemctl show <svc> -p Environment      # sanity-check (value visible to root only)
  ```
- **Docker Compose:** the value goes in the stack's `chmod 600` `.env`
  (git-ignored), referenced as `${VAR}`. Apply with
  `docker compose -f <stack> up -d`, not `restart`.
- **Files the app reads:** write to a temp file, `chmod 600`, `chown` to the
  service user, then `mv` into place (atomic), then signal the app
  (`systemctl reload` / `SIGHUP` / restart).
- **Never** commit the value, echo it into your shell history
  (`export X=...` is in `~/.bash_history`: prefix a space or use `read -s`),
  or paste it into a ticket/chat. Put a *pointer* ("rotated 2026-05, in
  Vault at path X") in your notes, not the secret.

## Verify

```bash
# API token: a cheap authenticated call
curl -fsS -H "Authorization: Bearer $NEW" https://api.example.com/v1/whoami

# DB password: connect and run a no-op
PGPASSWORD="$NEW" psql -h db -U svc -c 'select 1' >/dev/null && echo ok

# service came back healthy on the new value
systemctl is-active <svc>; journalctl -u <svc> --since '2 min ago' -p warning
```

Check the **provider's** access/audit log to confirm the new credential is
being used and the old one has gone quiet.

## After rotation

- Revoke the old value in the provider (don't just stop using it).
- Purge it from anywhere it was stored insecurely: git history
  (`git filter-repo`), old backups, log files, chat.
- If it was in a git repo: rotating **moots** the exposure, but also add the
  path/pattern to `.gitignore` and a pre-commit secret scanner (`gitleaks`,
  `git-secrets`) so it can't recur.
- Update your secrets inventory: what, where, when rotated, next due.
- If this was incident-driven, finish the
  [postmortem](incident-postmortem-template.md): how did it leak, what
  detected it, what prevents the next one.

## Per-type quick notes

| Secret | Extra steps |
|--------|-------------|
| **SSH key** | Add the new pubkey to `authorized_keys` *first*, test login in a second session, then remove the old line. Update `~/.ssh/config`. Rotate the key's passphrase separately with `ssh-keygen -p`. |
| **TLS private key / cert** | Reissue the cert with a fresh key (don't reuse the keypair). Reload the server (`nginx -s reload`, `systemctl reload caddy`). Check the served chain with `openssl s_client -connect host:443`. |
| **Database user password** | `ALTER USER svc WITH PASSWORD '...'`: existing sessions stay connected; only new connects use it. Restart the app to force reconnection. |
| **API token with scopes** | Issue the new one with the *same or narrower* scopes; over-scoped replacements are a common drift. |
| **Shared account** | Rotating a shared secret logs everyone out: announce it. Better: replace with per-user credentials while you're here. |
| **Cloud provider key** | Check for it in CI, IaC state, `~/.aws`/`~/.config`, and any serverless env before revoking. |
