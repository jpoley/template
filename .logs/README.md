# .logs

Append-only JSONL logs of agent decisions and the references consulted to reach them. Persistent across conversations; one file **per session** so sessions stay distinguishable and small.

## File naming

`YYYY-MM-DDTHHMMSSZ-<agent>-<short-id>.jsonl`

- Timestamp is the **session start**, UTC.
- `<agent>` is e.g. `claude-code`, `copilot`, `codex`.
- `<short-id>` is 6 hex chars (unique per session) so multiple sessions on the same second don't collide.

Example: `2026-04-22T135512Z-claude-code-a1b2c3.jsonl`.

## How to create a session file

Use the helper — it prints the path of the new file to stdout:

```bash
./.logs/new-session.sh claude-code
# → .logs/2026-04-22T135512Z-claude-code-a1b2c3.jsonl
```

Then append one JSON object per line as you go.

## Schema

Each line is a JSON object. Required fields:

```json
{
  "ts": "2026-04-22T14:32:05Z",
  "session": "2026-04-22T135512Z-claude-code-a1b2c3",
  "type": "decision" | "reference" | "note",
  "task": "TASK-23",
  "agent": "claude-code",
  "summary": "one-sentence summary"
}
```

Type-specific fields:

### `decision`

```json
{
  "ts": "…",
  "session": "…",
  "type": "decision",
  "task": "TASK-23",
  "agent": "claude-code",
  "summary": "Chose B_Standard_B1ms for dev Postgres, GP tier for prod.",
  "rationale": "Dev traffic is bursty and the burstable tier is cheap; prod needs predictable IOPS.",
  "alternatives_considered": ["GP for both", "B for both"],
  "links": ["backlog/decisions/decision-2 - Use-PostgreSQL-as-primary-store.md"]
}
```

### `reference`

```json
{
  "ts": "…",
  "session": "…",
  "type": "reference",
  "task": "TASK-23",
  "agent": "claude-code",
  "summary": "Consulted Azure Database for PostgreSQL Flexible Server pricing page.",
  "url": "https://learn.microsoft.com/azure/postgresql/flexible-server/concepts-pricing-tiers",
  "quote": "The Burstable compute tier is best suited for workloads that don't need the full CPU continuously."
}
```

### `note`

Free-form observations that don't warrant a decision record but might matter later.

## Do

- Log **why**, not what.
- Quote primary sources when you rely on them — docs change, quotes are archival.
- Link to commits, files, or PRs (`"links": ["commit:abc123", "TASK-12"]`).

## Don't

- Log every file read — noise.
- Log secrets. Ever.
- Edit past lines. Append-only. If something was wrong, log a correction with `"type": "note"` and `"correction_of": "<ts of bad entry>"`.
