---
id: TASK-3
title: Configure Terraform remote state
status: To Do
assignee: []
created_date: '2026-04-22 09:57'
labels:
  - infra
  - setup
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Uncomment the backend azurerm block in infra/providers.tf, create the state storage account (see infra/README.md), and run terraform init with the backend config.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 terraform init succeeds against the azurerm backend
<!-- AC:END -->
