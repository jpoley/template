# Record envelope

Every JSONL line is one record: envelope + payload. `kind` is the discriminator.

```json
{
  "id": "01JT8K...",
  "parent_id": "01JT8H...",
  "schema_version": "1",
  "phase": "design",
  "kind": "adr",
  "tool": "claude-code",
  "timestamp": "2026-04-26T14:02:33Z",
  "refs": { "prd": "01JT8H..." },
  "payload": { ... }
}
```

ULIDs (not UUIDv4) so lexicographic order = chronological order — useful for `sort` and bisect on the file. `parent_id` chains phases; `refs` carries any other cross-links. JSONL (not JSON) because the workflow is append-only and you want line-oriented tooling (`grep`, `jq -c`, streaming validation).

# Per-phase payloads

**PRD (`phase:plan`, `kind:prd`)**
```json
{
  "title": "...",
  "problem": "...",
  "goals": ["..."],
  "non_goals": ["..."],
  "constraints": ["..."],
  "success_criteria": ["..."],
  "open_questions": ["..."],
  "content_md": "<full PRD markdown>"
}
```

**ADR (`phase:design`, `kind:adr`)**
```json
{
  "title": "...",
  "status": "proposed|accepted|superseded",
  "context": "...",
  "decision": "...",
  "alternatives": [{"name":"...","rejected_because":"..."}],
  "consequences": {"positive":["..."],"negative":["..."]},
  "content_md": "<full ADR markdown>"
}
```

**Code (`phase:implement`, `kind:code`)**
```json
{
  "branch": "feat/xyz",
  "commit_sha": "abc123",
  "files": [{"path":"src/x.ts","op":"add|modify|delete","loc_added":42,"loc_removed":3}],
  "tests_added": ["tests/x.test.ts"],
  "diff_ref": "git:abc123"
}
```

**PR (`phase:test`, `kind:pr`)**
```json
{
  "pr_url": "https://github.com/org/repo/pull/123",
  "ci_status": "passing|failing|pending",
  "tests": {"passed": 42, "failed": 0, "skipped": 1},
  "coverage_pct": 87.4,
  "review_status": "open|approved|merged"
}
```

Rule: PRDs and ADRs go inline as `content_md` (small, single source of truth). Code diffs do **not** go inline — reference by `commit_sha` / `diff_ref`. Otherwise the JSONL becomes a diff store.

# Schema

JSON Schema 2020-12 — pick it because every language has a validator (ajv, python-jsonschema, jsonschema-rs) and it's what most CI pipelines already speak. Alternative would be Pydantic/Zod that emit JSON Schema; fine if you want one source language, but the published artifact should still be the JSON Schema.

One envelope schema dispatches to four payload schemas via `if/then`:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://daax.dev/spec/v1/record.json",
  "type": "object",
  "required": ["id","schema_version","phase","kind","tool","timestamp","payload"],
  "properties": {
    "id":             {"type":"string","pattern":"^[0-9A-HJKMNP-TV-Z]{26}$"},
    "parent_id":      {"type":["string","null"]},
    "schema_version": {"const":"1"},
    "phase":          {"enum":["plan","design","implement","test"]},
    "kind":           {"enum":["prd","adr","code","pr"]},
    "tool":           {"type":"string"},
    "timestamp":      {"type":"string","format":"date-time"},
    "refs":           {"type":"object"},
    "payload":        {"type":"object"}
  },
  "allOf": [
    {"if":{"properties":{"kind":{"const":"prd"}}},
     "then":{"properties":{"phase":{"const":"plan"},"payload":{"$ref":"prd.json"}}}},
    {"if":{"properties":{"kind":{"const":"adr"}}},
     "then":{"properties":{"phase":{"const":"design"},"payload":{"$ref":"adr.json"}}}},
    {"if":{"properties":{"kind":{"const":"code"}}},
     "then":{"properties":{"phase":{"const":"implement"},"payload":{"$ref":"code.json"}}}},
    {"if":{"properties":{"kind":{"const":"pr"}}},
     "then":{"properties":{"phase":{"const":"test"},"payload":{"$ref":"pr.json"}}}}
  ]
}
```

The paired `if/then` blocks lock `phase` to `kind` so you can't emit `phase:plan` with `kind:adr`.

# Validator

Two layers — schema alone isn't enough.

**L1 (per-line):** run JSON Schema against each line.

**L2 (cross-record invariants):**
- `id` is unique across the file.
- `parent_id` resolves to a prior line in the same file.
- Phase chain: `adr.parent.kind == prd`, `code.parent.kind == adr`, `pr.parent.kind == code`. Branching allowed (multiple ADRs per PRD, etc.); skipping not allowed.
- `tool` is in a registered set (warn, not error, so new tools don't break CI).

CLI: `spec validate runs/<id>.jsonl` → exit 0/1, machine-readable JSON output for CI.

# Repository layout

```
spec/
  v1/
    schema/
      record.json        envelope + dispatch
      prd.json
      adr.json
      code.json
      pr.json
    prompts/             tool-agnostic, per-phase
      plan.md
      design.md
      implement.md
      test.md
    skills/              SKILL.md per phase
      plan/SKILL.md
      design/SKILL.md
      implement/SKILL.md
      test/SKILL.md
    tools/               per-tool adapters
      claude-code/
        commands/plan.md      # the /plan slash command body
        commands/design.md
        commands/implement.md
        commands/test.md
      cursor/
      aider/
      codex/
    examples/
      happy-path.jsonl
    validate/
      validator.ts | validator.py
```

# Prompt vs skill — what goes where

This split matters; collapse it and you'll regret it when adding the second tool.

**Prompt** = *what to produce*. The contract: inputs, output shape, JSONL record it must emit, guardrails. Lives in `prompts/<phase>.md`. Should be readable in isolation and reusable across tools.

**Skill** = *how to do it*. Procedural domain knowledge: how to interview a user for a PRD, how to detect missing constraints in an ADR, how to choose a test strategy. Lives in `skills/<phase>/SKILL.md`, follows Anthropic's skill convention (frontmatter + body, loaded on demand).

**Tool adapter** = *glue*. `tools/claude-code/commands/plan.md` is the actual slash command body. It loads the phase prompt + skill, knows tool-specific affordances (file I/O paths, MCP calls, how to append to the JSONL), then runs the validator before returning.

You write the prompt and skill once. You write a thin adapter per tool.

# /plan end-to-end

1. User runs `/plan <feature>` in Claude Code (or whatever).
2. Adapter loads `prompts/plan.md` + `skills/plan/SKILL.md`.
3. Agent produces PRD: writes `docs/prd/<ulid>.md` and the structured fields.
4. Adapter appends one line to `runs/<run-id>.jsonl` with `kind:prd`, `phase:plan`, `payload.content_md` inline.
5. Pre-commit hook runs `spec validate` — block on failure.
6. `/design` reads the latest `kind:prd` record, sets it as `parent_id`, emits `kind:adr`.
7. `/implement` reads latest accepted `kind:adr`, produces commit, emits `kind:code` with `commit_sha`.
8. `/test` opens PR, polls CI, emits `kind:pr` with results.

A run = one JSONL file. The four-record happy path is one PRD → one ADR → one Code → one PR. Re-runs append; nothing is mutated.

# Versioning

`schema_version` is required on every record. Validator dispatches to `spec/v<n>/schema/...`. Bump on breaking changes only; additive changes go through `oneOf` extension. Keep old validators around so historical JSONL files stay valid.

# What this buys you

A deterministic, tool-agnostic audit trail. Any coding tool that can write JSONL participates. CI gate is one command. Adding a new tool is one adapter directory, no spec changes. Adding a new phase (e.g., `/review`) is one schema file + one prompt + one skill + adapter entries — the envelope doesn't move.
