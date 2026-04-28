---
id: TASK-6
title: Internal RBAC + Entra OIDC rollout
status: To Do
assignee:
  - claude-code
created_date: '2026-04-28 02:01'
labels:
  - area/multi
  - priority/high
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Execute docs/plan-internal-rbac.md in two PRs: PR1 (refactor/internal-nextjs-port) renames admin→internal and ports Vue→Next.js; PR2 (feat/entra-rbac) adds Entra OIDC + RBAC + worked example. Closed-loop tested via scripts/test-all.sh after each phase.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 PR1: internal/ exists; admin/ does not; scripts/test-all.sh green
- [ ] #2 PR2: §4.6 persona matrix asserted at unit/integration/e2e/smoke; production safety rail tested; docs/auth.md shipped
<!-- AC:END -->
