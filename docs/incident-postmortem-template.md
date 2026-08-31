# Incident Postmortem Template

A blameless postmortem structure for after an incident is resolved. Pairs
with [incident-response-runbook.md](incident-response-runbook.md), which
covers handling the incident while it's happening — this document is for
afterward, once things are calm and the goal shifts from "make it stop"
to "make sure it doesn't happen the same way again."

## Why blameless

The point of a postmortem is to find and fix the conditions that allowed
an incident to happen, not to find who to blame for it. A postmortem
that reads as an accusation teaches people to hide mistakes and near
misses instead of reporting them — which is exactly the information you
need to prevent a repeat. Write it as if the person who made the change
that triggered the incident is going to read it and feel safe doing so,
because they probably will.

Write every finding as a system or process gap ("the deploy pipeline
had no automated rollback on failed health checks") rather than a
personal one ("X deployed without checking Y first"). If a human step
was skipped, ask why the process made it easy to skip, not why the
person skipped it.

## When to write one

Not every incident needs a full writeup. A reasonable bar: anything that
paged someone outside business hours, caused customer-visible impact
beyond a few minutes, or very nearly did either of those (a "near miss"
is often more informative than an incident that was already well
understood). Use judgment — the goal is learning something, not
filling out paperwork.

## Template

### Summary
One or two sentences: what broke, for how long, who/what was affected.
Written so someone who wasn't involved understands the shape of it in
ten seconds.

### Timeline
Timestamped, in UTC (or a single consistent timezone, stated up front).
Include when the underlying issue was introduced if known, not just
when it was detected — the gap between those two is often the most
actionable part of the timeline.

```
14:02  Change X deployed to production
14:31  First alert fired (disk-usage-report.sh threshold, host db-2)
14:33  On-call acknowledged
14:41  Root cause identified: change X filled a log partition
14:47  Mitigation applied: log-cleanup.sh run manually, service restarted
15:05  Confirmed resolved, alert cleared
```

### Impact
Concretely: what was down or degraded, for how long, and who noticed —
customers, an internal team, nobody (a near miss). Avoid vague terms
like "some users" if you can find a real number or scope.

### Root cause
The technical cause, and — this is the part that's easy to skip — the
*contributing* causes that let it become an incident instead of a
non-event. A single root cause is rare; usually it's "change X plus the
fact that monitoring gap Y meant nobody caught it for 20 minutes."

### Detection
How was it found — an alert, a customer report, someone noticing by
chance? If it was found later than it should have been, that's itself
a finding: what would have caught it sooner (a
[log-anomaly-scan.sh](../scripts/log-anomaly-scan.sh) run more
frequently, a check that doesn't exist yet)?

### Response
What actually happened during mitigation, including any dead ends —
"we first suspected X and spent 10 minutes on it before finding the
real cause" is useful information, not something to omit for looking
tidy.

### What went well
Genuinely worth including — a good runbook, a fast page, a clean
rollback. Reinforces what to keep doing.

### What went poorly
The gaps: missing monitoring, a runbook that was out of date, a manual
step that should be scripted, an alert that didn't fire when it should
have.

### Action items
Each one: owner, and either a due date or an explicit decision not to
do it and why. An action item with no owner doesn't happen. Track these
somewhere that gets reviewed — a postmortem whose action items are
never revisited is a postmortem that didn't help.

### Appendix
Relevant logs, graphs, or command output. Link rather than paste where
the source is durable; paste where it might not be (a log line from a
host that's since been rebuilt).
