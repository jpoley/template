---
id: decision-2
title: Use Cosmos DB SQL API as primary store
date: '2026-04-22 09:58'
status: accepted
---
## Context

The project stores semi-structured, tenant-partitioned records with low-latency read needs and variable write volume. We want a managed service, pay-for-what-you-use scale, and first-class Azure integration.

## Decision

Use **Azure Cosmos DB, Core (SQL) API**: one account per environment, one database, one container (`items`) partitioned by `/partitionKey`.

## Consequences

- Horizontal scaling is free once partition key is well chosen — getting partition key right is load-bearing.
- Global replication is one toggle away.
- Cross-partition queries are expensive (RU-heavy) — design queries to stay within a single partition.
- Cosmos emulator (`mcr.microsoft.com/cosmosdb/linux/azure-cosmos-emulator:vnext-preview`) runs in `docker-compose.yml` for local dev. Uses the well-known emulator key; no HTTPS cert gymnastics.
- Production uses **managed identity**, never keys (see `infra/modules/container_apps/main.tf` role assignment).
