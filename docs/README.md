# Documentation

- [requirements.md](requirements.md) — what this project must do.
- [design.md](design.md) — system design, components, data flow.
- [architecture.md](architecture.md) — deployment topology, runtime boundaries, ops concerns.

Architecture decisions live in **`backlog/decisions/`** (managed by the `backlog` CLI — `backlog decision create`). Static, narrative docs live here.

## Conventions

- Docs live in Markdown. Diagrams in [Mermaid](https://mermaid.js.org/) so they render on GitHub without tooling.
- When a decision is made, record it in `backlog/decisions/` rather than editing history.
- Update `requirements.md` when scope changes — the file should always describe the *current* target.
