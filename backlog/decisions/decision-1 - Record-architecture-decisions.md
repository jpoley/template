---
id: decision-1
title: Record architecture decisions
date: '2026-04-22 09:57'
status: accepted
---
## Context

Structural decisions (tech choices, data models, boundaries) silently drift when they aren't written down. AI agents and new contributors end up reverse-engineering intent from code, which is slow and error-prone.

## Decision

Every structural decision gets a decision record in `backlog/decisions/`. Managed via `backlog decision create`. Records are append-only: when a decision is superseded, create a new record that links to the old one and flip the old one's status to `superseded`.

## Consequences

- Small up-front cost per decision.
- Decisions survive refactors and team turnover.
- New contributors and agents read decisions to catch up on *why* rather than reverse-engineering.
- Duplicates the ADR concept — keep docs/adr/ for legacy / imported ADRs but write new ones here.
