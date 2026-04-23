# Design

## System components

```mermaid
flowchart LR
  User([End user]) --> FE[Frontend<br/>Vue + SW]
  Admin([Admin]) --> AdminUI[Admin UI<br/>Vue]
  FE -->|/api| API[Backend API<br/>.NET 10]
  AdminUI -->|/api| API
  API --> PG[(PostgreSQL<br/>items table)]
  API --> Logs[(App Insights)]
```

## Data model

Single `items` table managed by EF Core. Rows:

```json
{
  "id": "guid",
  "partitionKey": "tenant-or-user-id",
  "name": "string",
  "description": "string?",
  "createdAt": "ISO-8601",
  "updatedAt": "ISO-8601"
}
```

`partitionKey` is retained as a tenant/user discriminator column — index it for the common query shape (all items for a given tenant).

## API surface

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/api/health` | Liveness |
| GET | `/api/items/{pk}` | List items for a partition key |
| GET | `/api/items/{pk}/{id}` | Read one item |
| POST | `/api/items` | Create item |
| PUT | `/api/items/{pk}/{id}` | Update item |
| DELETE | `/api/items/{pk}/{id}` | Delete item |

See `/scalar` on the backend in Development for live API docs.

## Key decisions

See `backlog/decisions/` for individual decisions and their rationales (`backlog decision list`).
