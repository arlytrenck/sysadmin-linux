# Change Management Checklist

A pre/post-change checklist for changes to a production Linux host —
config edits, package installs, service changes, anything that isn't
pure read-only investigation. Scaled for a homelab or small fleet: not
a formal change-advisory-board process, just the minimum discipline
that keeps a bad change from becoming an incident. Pairs with
[capacity-planning-guide.md](capacity-planning-guide.md) for the
review cadence a routine change might warrant, and with
[incident-postmortem-template.md](incident-postmortem-template.md) for
when a change goes wrong anyway.

## Before the change

- [ ] **Written down what's changing and why**, even briefly — a commit
  message, a ticket, or a line in a shared doc. Future-you (or whoever
  investigates a later incident) needs to be able to find this.
- [ ] **Confirmed a recent, verified backup exists** for anything the
  change touches — see
  [database-backup-restore-guide.md](database-backup-restore-guide.md)
  for databases, or the relevant config/data path otherwise. "Verified"
  means tested restorable, not just "a backup job ran."
- [ ] **Identified the rollback path** before starting, not after
  something goes wrong. For config changes, this is usually "keep the
  old file" (`cp file file.bak.$(date +%s)` costs nothing). For package
  changes, know whether a downgrade is straightforward.
- [ ] **Checked for a maintenance window / notified anyone who needs to
  know**, if the change could cause visible disruption — including
  silencing alerts tied to the expected disruption so real problems
  aren't lost in the noise.
- [ ] **Considered blast radius.** Can this be tested on one host before
  the rest of the fleet? A canary host, even an informal one, catches
  most "this breaks on real config" problems cheaply.

## During the change

- [ ] **One change at a time.** Bundling multiple unrelated changes
  makes rollback and root-causing much harder if something breaks —
  you won't know which part did it.
- [ ] **Capture the exact commands run**, not just the intent — shell
  history is not a durable record; a scrollback paste or script is.

## After the change

- [ ] **Verified the change had the intended effect**, not just "the
  command didn't error." Check the actual state (a config reload
  succeeded, a service is listening, a value changed) —
  [service-health-check.sh](../scripts/service-health-check.sh) and
  [security-audit.sh](../scripts/security-audit.sh) are useful generic
  checks depending on what changed.
- [ ] **Watched for regressions for a reasonable window afterward**, not
  just at the moment of the change —
  [log-anomaly-scan.sh](../scripts/log-anomaly-scan.sh) can catch a
  problem that only shows up once real traffic returns.
- [ ] **Re-enabled anything silenced** for the maintenance window.
- [ ] **Updated any documentation the change invalidated** — a runbook,
  an inventory, a diagram. Stale docs are worse than no docs, because
  they're trusted.
- [ ] **Removed the rollback artifact once confident the change is
  good** (or explicitly decided to keep it longer) — don't let
  `file.bak.171234` accumulate indefinitely as an unreviewed pile.

## When a change goes wrong

Roll back using the path identified before starting, rather than trying
to forward-fix under pressure — a forward fix invented while something
is actively broken is itself an unreviewed, untested change. If the
incident was more than trivial, write it up using
[incident-postmortem-template.md](incident-postmortem-template.md).
