---
id: TASK-5
title: Verify local stack boots
status: To Do
assignee: []
created_date: '2026-04-22 09:57'
labels:
  - smoke-test
  - setup
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Start Docker Desktop, run 'docker compose up --build'. Confirm frontend at :5173, admin at :5174, backend health at :8080/api/health, Cosmos emulator at :8081.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 All four services report healthy in docker compose ps
<!-- AC:END -->
