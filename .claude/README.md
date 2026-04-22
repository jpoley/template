# .claude

Project-level Claude Code configuration.

- `../CLAUDE.md` — top-level instructions loaded by Claude Code (lives at repo root so it loads for any working directory under the repo).
- `settings.json` — permission allow/deny list for this project.
- `agents/` — project-scoped subagent definitions.

To add a new subagent, drop a Markdown file in `agents/` with frontmatter (see `agents/reviewer.md`).
