## Summary

<!-- What and why in 1–3 sentences. -->

## Scope

- [ ] frontend
- [ ] internal
- [ ] backend
- [ ] infra
- [ ] docs
- [ ] CI / tooling

## Changes

<!-- Bullet list of notable changes. -->

## Validation

- [ ] `bun run typecheck` / `bun run test` pass (if frontend/internal touched)
- [ ] `dotnet build /warnaserror` and `dotnet test` pass (if backend touched)
- [ ] `terraform fmt -check` and `terraform validate` pass (if infra touched)
- [ ] `docker compose up --build` boots cleanly (if Dockerfiles or compose changed)

## Docs

- [ ] `docs/requirements.md` updated (scope change)
- [ ] `docs/design.md` updated (behavior change)
- [ ] New ADR in `docs/adr/` (architectural change)
- [ ] N/A

## Risk

<!-- Is this reversible? What breaks if it goes wrong? -->
