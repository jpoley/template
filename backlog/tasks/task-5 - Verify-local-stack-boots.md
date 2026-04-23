---
id: TASK-5
title: Verify local stack boots
status: To Do
assignee: []
created_date: '2026-04-22 09:57'
updated_date: '2026-04-23 16:57'
labels:
  - smoke-test
  - setup
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Start Docker Desktop, run 'docker compose up --build' (or './rebuild.sh'). Confirm frontend at :6173, admin at :6174, backend health at :6180/api/health, Postgres at :6432.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 All four services report healthy in docker compose ps
<!-- AC:END -->
