# Plan: rename `admin/` → `internal/`, port Vue → Next.js, add Entra OIDC + RBAC

Status: **DRAFT — awaiting approval before any implementation.**
Author: Claude + Jason
Last updated: 2026-04-27

## 0. Context

The template currently ships two SPAs (`frontend/` Vue + `admin/` Vue) and a .NET 10 Minimal API with no auth. We are making three coordinated changes:

1. Rename `admin/` → `internal/` to better reflect role (internal staff tooling, not just admin).
2. Re-implement `internal/` as a **Next.js 15** app (App Router, React, shadcn). The template demonstrates two distinct frontend stacks: `frontend/` stays Vite + Vue + shadcn-vue (pure SPA reference); `internal/` becomes Next.js + shadcn (SSR / admin-grade reference). Consumers of the template can pick the shape that fits.
3. Add Entra ID-based authentication (OIDC, cookie-backed) plus a containerized OIDC mock for dev/CI/smoke. Add role-based, **fine-grained**, **element-level** authorization with roles + permissions stored in our Postgres DB.

The .NET 10 Minimal API stays. A "Plan B" for migrating the backend to a Bun/Node runtime is sketched in §7 as a contingency design, not implemented in this work.

The work splits into two PRs / two branches. PR 1 is structural (rename + framework swap; no behavior change). PR 2 is the auth + RBAC feature.

## 1. Non-goals

- User registration. Users are managed in Entra. First login JIT-provisions a `Users` row.
- Password storage. `Microsoft.Identity.Web` (prod) and the OIDC mock (dev) handle credentials.
- Role seeding in production migrations. Roles are operator-defined per deployment. Only test-fixture roles are seeded, and only in dev.
- LDAP, SAML, basic auth, or any non-OIDC IdP.
- A separate admin SPA. Internal *is* where role/user management lives.
- Migrating `frontend/` (Vue) to React or Next.js.
- Migrating the .NET backend. Stays as-is for both PRs. §7 documents a Plan B (Bun + Hono + Drizzle) as a contingency design.

## 2. Architecture

### 2.1 Auth flow — one code path, two issuers

```
[SPA] --GET /api/auth/login?return=/--> [Backend]
[Backend] --302 to ${OIDC_ISSUER}/authorize?...--> [IdP]
[IdP: Entra in prod, mock-oauth2-server in dev] --302 with code--> [Backend /signin-oidc]
[Backend] --token exchange + cookie issuance--> [SPA at `return` URL]
[SPA] --GET /api/auth/me (cookie)--> [Backend] --200 { user, roles, permissions }--> [SPA]
```

A single env var (`OIDC_ISSUER`) chooses the IdP. Cookie auth: httpOnly, SameSite=Lax, signed, sliding 8h expiration. All API endpoints check the cookie via the standard ASP.NET Core authorization pipeline.

### 2.2 Mock OIDC IdP for dev/CI/smoke

- Service `oidc` in `docker-compose.yml`, image `ghcr.io/navikt/mock-oauth2-server` (tag pinned to a specific minor).
- Config mounted from `infra/dev/mock-oidc.json` defining the 5 test personas.
- Backend points at `http://oidc:8080/template` for `OIDC_ISSUER`.
- Real OIDC discovery, real JWKs, real signed tokens — same code path Entra exercises in prod.

### 2.3 Entra ID in prod

- Single-tenant app registration. Client ID + tenant ID in env. Client secret in Azure Key Vault, referenced by Container Apps managed identity.
- `OIDC_ISSUER` set to `https://login.microsoftonline.com/${TENANT_ID}/v2.0`.
- Required scopes: `openid profile email`. No Microsoft Graph access; we don't enumerate the directory.

### 2.4 RBAC data model

New EF Core entities, single migration:

- `Users(id GUID, external_id text UNIQUE, email text, display_name text, created_at, last_login_at)`
- `Roles(id GUID, key text UNIQUE, display_name, created_at)`
- `Permissions(id GUID, key text UNIQUE, display_name, description, is_active bool)`
- `UserRoles(user_id, role_id)` join
- `RolePermissions(role_id, permission_id)` join

Design points:

- **Permissions are code-defined, DB-reconciled.** App startup ensures every key registered via `IPermissionRegistry` exists in `Permissions`. Removed permissions stay (FK safety) but flip `is_active=false`.
- **Roles are operator-defined.** Created via `/internal/admin/roles`. No production seeds.
- **Test fixtures seed roles only when `OIDC_ISSUER` host is in {`oidc`, `localhost`, `127.0.0.1`}.** Host-based detection — one less env-flag footgun.
- **Authorization combines role-based + record-based.** `IItemAuthorizationPolicy.CanEdit(ClaimsPrincipal, Item)` checks role grant *and* (where relevant) ownership/state.

### 2.5 API surface

```
POST   /api/auth/login              # 302 → IdP
POST   /api/auth/logout             # clear cookie + 302 → IdP signout
GET    /api/auth/config             # { provider: "entra" | "test" }
GET    /api/auth/me                 # { id, email, displayName, roles[], permissions[] }
GET    /api/auth/test/personas      # only registered when test issuer is active

GET    /api/items                   # items:read; row filter applied per user
GET    /api/items/:id               # field projection + _permissions per user
POST   /api/items                   # items:write
PUT    /api/items/:id               # IItemAuthorizationPolicy.CanEdit
DELETE /api/items/:id               # IItemAuthorizationPolicy.CanDelete
POST   /api/items/:id/approve       # items:approve

GET    /api/admin/users             # users:manage
GET    /api/admin/users/:id         # users:manage
PUT    /api/admin/users/:id/roles   # users:manage

GET    /api/admin/roles             # roles:manage
POST   /api/admin/roles             # roles:manage
GET    /api/admin/roles/:id         # roles:manage
PUT    /api/admin/roles/:id         # roles:manage
DELETE /api/admin/roles/:id         # roles:manage; only when no users assigned

GET    /api/admin/permissions       # roles:manage; lists registered keys
```

DTOs include a `_permissions` object computed server-side per user per resource:

```json
{
  "id": "...",
  "title": "Widget #42",
  "description": "...",
  "approvedAt": "2026-04-20T12:00:00Z",
  "auditNotes": "<present iff user has audit:read>",
  "internalNotes": "<present iff superuser>",
  "_permissions": { "edit": true, "delete": false, "approve": false }
}
```

Server is authoritative twice: it both **shapes the DTO** (omitting fields the user can't see) and **reports per-resource permissions** (so the UI doesn't re-implement the policy).

### 2.6 Permission keys (template demo)

Registered by `ProjectTemplate.Api` at startup. Consumers replace these.

| Key | Description |
|---|---|
| `items:read` | View items |
| `items:write` | Create/edit items |
| `items:delete` | Delete items |
| `items:approve` | Toggle approval state |
| `audit:read` | View audit notes / change history |
| `users:manage` | Assign roles to users |
| `roles:manage` | Create/edit/delete roles, attach permissions |

### 2.7 Test personas

Identities in `infra/dev/mock-oidc.json`. Role assignments via dev-only EF seed.

| Persona | external_id | email | Granted role | Effective permissions |
|---|---|---|---|---|
| Viewer | viewer-1 | viewer@test.local | TestViewer | items:read |
| Editor | editor-1 | editor@test.local | TestEditor | items:read, items:write |
| Approver | approver-1 | approver@test.local | TestApprover | items:read, items:approve |
| Auditor | auditor-1 | auditor@test.local | TestAuditor | items:read, audit:read |
| Superuser | superuser-1 | super@test.local | TestSuperuser | all of the above + users:manage + roles:manage + items:delete |

The `Test*` roles are dev-only fixtures. They demonstrate the pattern; consumers don't ship them.

### 2.8 UI gating primitives — both apps

```
<RequirePermission permission="items:write" fallback={...}>
  ...rendered only when granted...
</RequirePermission>

<DisableWithoutPermission
  permission="items:delete"
  resourcePermission={item._permissions.delete}>
  <Button>Delete</Button>          // disabled + tooltip if not granted
</DisableWithoutPermission>

<ReadOnlyWithoutPermission
  permission="items:write"
  resourcePermission={item._permissions.edit}>
  <Input value={item.title} />     // readonly if not granted
</ReadOnlyWithoutPermission>

const { user, can } = useAuth();
{can('items:write') && <Button>New</Button>}
```

`resourcePermission` (when provided) **AND-gates** with the user's global permission. This is how record-level rules ("editors can only edit items they own") flow to the UI — the server computes the policy once, the client just reads the boolean.

The unit of gating is the **element**, not the screen. Two users on the same URL see materially different views: different fields, different actions, different data in the response. The worked example (§4.5) demonstrates every primitive on a single screen so a developer copying the template sees the patterns.

### 2.9 Production safety rail

App startup refuses to boot if `OIDC_ISSUER` resolves to a private/loopback hostname **and** `ASPNETCORE_ENVIRONMENT=Production`. Hard fail with a fatal log line. Prevents a copy-pasted `.env.example` from shipping the dev IdP to prod. Tested in §4.8.1.

---

## 3. PR 1 — Rename + Vue→Next.js port (no auth changes)

Branch: `refactor/internal-nextjs-port`

### 3.1 Scope

- `admin/` → `internal/` (`git mv` for path history; contents fully replaced).
- Vue 3 SPA rewritten as **Next.js 15 (App Router) + React 19 + TypeScript**.
- Stack: `next@15`, `react@19`, `react-dom@19`, `@tanstack/react-query@5`, `tailwindcss@4`, `shadcn` (React), `lucide-react`. ESLint flat config with `eslint-config-next` + `typescript-eslint`.
- Output mode: `output: "standalone"` — Next.js produces a self-contained Node bundle. Container runs `node server.js` on a slim Node 22 base image. **No nginx in `internal/`.**
- Same external behavior: same routes (`/`, `/items`), same API calls to `/api/items`. Port number is not load-bearing — compose maps whatever Next.js binds.
- All cross-references updated: compose, Dockerfile, GitHub Actions, e2e, Terraform, scripts, docs, CLAUDE.md, README.
- `frontend/` (Vite + Vue + shadcn-vue) is **unchanged** in this PR.
- `backend/` (.NET 10 Minimal API) is **unchanged** in this PR.

### 3.2 File inventory

**Renamed:**
- `admin/` → `internal/`

**Net new (Next.js scaffolding):**
- `internal/next.config.ts` — App Router, `output: "standalone"`
- `internal/next-env.d.ts` — Next.js generated; tracked
- `internal/src/app/layout.tsx` — root layout (HTML shell, Tailwind import, providers)
- `internal/src/app/page.tsx` — dashboard (replaces `views/DashboardView.vue`)
- `internal/src/app/items/page.tsx` — items list (replaces `views/ItemsView.vue`)
- `internal/src/app/globals.css` — Tailwind directives (relocated from `src/styles/globals.css`)
- `internal/src/app/providers.tsx` — `'use client'` wrapper around `<QueryClientProvider>`; consumed by `layout.tsx`

**Rewritten in Next.js (same conceptual file, new content):**
- `internal/package.json` — name `@projecttemplate/internal`; scripts `dev` / `build` / `start` / `lint` use `next`
- `internal/tsconfig.json` — Next.js baseline + path alias `@/*` → `src/*`
- `internal/eslint.config.js` — `eslint-config-next` flat config
- `internal/components.json` — fresh shadcn (React, Next.js install path)
- `internal/Dockerfile` — multi-stage: builder runs `bun install` + `bun run build`; runner is `node:22-bookworm-slim`, copies `.next/standalone/`, `.next/static/`, and `public/`; `CMD ["node", "server.js"]`
- `internal/src/lib/api.ts` — fetch wrappers; client paths stay same-origin (Next.js `/api/*` rewrite proxies to `API_PROXY_TARGET`); RSC paths forward the request cookie via `next/headers`
- `internal/src/lib/utils.ts` — `cn()` carried forward
- `internal/src/lib/types.ts` — DTOs carried forward
- `internal/src/components/ui/button.tsx` — re-added via `bunx shadcn@latest add button`
- `internal/src/__tests__/smoke.test.tsx` — RTL smoke; renders a client component

**Removed (no Next.js equivalent):**
- All `*.vue` files
- `admin/index.html` (Next.js owns the document via `app/layout.tsx`)
- `admin/vite.config.ts`
- `admin/nginx.conf` (Node runtime serves directly; no static webserver layer)
- `admin/tsconfig.node.json`
- `admin/src/main.ts`, `admin/src/App.vue`, `admin/src/router/`, `admin/src/views/`, `admin/src/env.d.ts`, `admin/src/styles/`
- old `admin/components.json`

**Updated cross-references:**
- `docker-compose.yml` — service `admin` → `internal`; build context `./internal`; healthcheck against the Next.js HTTP port; `NODE_ENV=production` for the runner
- `.github/workflows/admin.yml` → `.github/workflows/internal.yml` — paths, job names, image tags; CI uses Node 22 for `next build` (see §3.3)
- `.github/workflows/build-images.yml` — image refs
- `.github/workflows/e2e.yml` — service refs
- `.github/dependabot.yml` — `/admin` → `/internal`
- `.github/PULL_REQUEST_TEMPLATE.md`, `.github/ISSUE_TEMPLATE/*.yml` — references
- `e2e/tests/admin.spec.ts` → `e2e/tests/internal.spec.ts` — file rename + URL targets
- `e2e/tests/screenshots.spec.ts`, `e2e/playwright.config.ts`, `e2e/README.md`
- `infra/main.tf`, `infra/variables.tf`, `infra/outputs.tf`
- `infra/modules/container_apps/main.tf` — admin → internal app definitions; container target port matches Next.js
- `infra/modules/frontdoor/main.tf` — routing rules
- `infra/modules/registry/main.tf` — image name
- `infra/README.md`
- `scripts/test-all.sh`, `scripts/smoke.sh`, `scripts/ci.sh`, `rebuild.sh`
- `install/install-deps.sh`, `install/install-docker-rootless.sh`
- `docs/architecture.md`, `docs/testing.md`, `docs/debugging-in-container.md`, `docs/enterprise-proxy.md`, `docs/requirements.md`, `docs/troubleshooting/port-conflicts.md`
- `README.md`
- `CLAUDE.md` — repo map, frontend conventions (Vite+Vue + Next.js+React split)
- `backlog/tasks/task-5 - Verify-local-stack-boots.md`
- `.github/copilot-instructions.md`

### 3.3 Next.js stack rationale

| Vue choice | Next.js equivalent | Note |
|---|---|---|
| `vue@3.5` | `react@19` + `next@15` | Next.js 15 is App Router-stable |
| `vue-router@5` | App Router (file-based) | `app/items/[id]/page.tsx` etc. — no router lib needed |
| `@tanstack/vue-query` | `@tanstack/react-query@5` | Wrapped in a `'use client'` provider exposed via `app/providers.tsx` |
| `pinia` | (none) | Server state via react-query; UI state via `useState` |
| `@vueuse/core` | (none) | React built-ins suffice; `react-use` only if a specific hook is needed |
| `radix-vue` | `@radix-ui/react-*` | Primitives shadcn React uses |
| `lucide-vue-next` | `lucide-react` | Direct port |
| `vue-tsc` | `tsc` (built into `next build`) | Next.js validates types during build |
| shadcn-vue | shadcn (React, Next.js install path) | Next.js is shadcn's primary documented target |
| Vite | Next.js (Webpack/Turbopack) | Different build tool; `bun run dev` still the dev command |
| nginx serving `dist/` | `node server.js` (standalone) | Runtime change; ~80 MB Node image vs ~30 MB nginx |

**Bun support note**: Next.js 15 works with Bun for `bun install` and `bun run dev`. Production `next build` is officially Node-tested but works with Bun in practice. The Dockerfile uses **Bun for installs in the builder stage** and **Node for the runtime stage** — matches Vercel's recommended runtime while keeping the rest of the JS toolchain on Bun. CI builds with Node 22 to minimize Bun-only edge cases.

### 3.4 Acceptance criteria — PR 1

- [ ] `internal/` exists; `admin/` does not.
- [ ] `cd internal && bun install && bun run dev` boots Next.js (`next dev`) and renders dashboard + items pages.
- [ ] `cd internal && bun run lint` passes (zero errors; `next lint`).
- [ ] `cd internal && bun run test` passes (RTL smoke test via Vitest).
- [ ] `cd internal && bun run build` succeeds (`next build`); produces `.next/standalone/` and `.next/static/`; exits 0.
- [ ] `cd internal && bun run start` runs `node .next/standalone/server.js` and serves HTTP successfully.
- [ ] Type checking via `next build` passes with zero errors (Next.js fails the build on TS errors).
- [ ] `docker compose up --build` boots the renamed service; the Next.js container responds with HTML on its mapped port.
- [ ] `scripts/smoke.sh` passes — full closed loop, including the Next.js app responding with HTML and CRUD round-trip against `/api/items` succeeding.
- [ ] `scripts/test-all.sh` passes end-to-end with no failures.
- [ ] e2e tests in `e2e/tests/internal.spec.ts` pass against compose.
- [ ] CI workflow `internal.yml` is green.
- [ ] `frontend/` (Vue) is unchanged: `cd frontend && bun run typecheck && bun run test && bun run build` all pass.
- [ ] `backend/` is unchanged: `dotnet test` from `backend/` passes.
- [ ] `terraform fmt -check && terraform validate && tflint` pass under `infra/`.
- [ ] `rg -l '\\badmin\\b' --type-not md --glob '!{node_modules,bin,obj,.git,backlog/decisions}'` returns no surprising hits. Allowed contexts: copy referring to a future "administrator" role display name, historical log entries.

### 3.5 Test plan — PR 1

| Layer | What | Where | Pass criterion |
|---|---|---|---|
| Static | TypeScript compile | `bun run build` in `internal/` | `next build` exits 0 (TS errors fail the build) |
| Static | ESLint | `bun run lint` in `internal/` | Zero errors |
| Unit | App smoke | `internal/src/__tests__/smoke.test.tsx` | Vitest + RTL; renders a client component, asserts dashboard heading |
| Unit | API client | `internal/src/__tests__/api.test.ts` | Mocks `fetch`; verifies request shapes |
| Build | Next.js production build | `bun run build` | Produces `.next/standalone/` + `.next/static/`; exits 0 |
| Container | Docker image | `docker compose build internal` | Image builds and starts; Node runs `server.js` |
| Integration | Internal serves HTML | `curl -fsS http://localhost:<port> \| grep -qiE '<html\|<!doctype html'` | HTML returned by Next.js |
| Integration | App loads bundle | Playwright: `page.goto('/'); expect(page.locator('h1')).toBeVisible()` | Page interactive |
| E2E | CRUD via SPA | `e2e/tests/internal.spec.ts`: open `/items`, create, verify | Item appears |
| Smoke | Full stack | `scripts/smoke.sh` | All checks green |
| Regression | Backend | `dotnet test` from `backend/` | All passing |
| Regression | `frontend/` | `bun run typecheck && bun run test` | All passing |
| Regression | Terraform | `terraform fmt -check && terraform validate && tflint` | Zero diffs/errors |

### 3.6 Rollback — PR 1

Single atomic merge. Rollback = revert the merge commit. No data migrations. No production traffic implications.

---

## 4. PR 2 — Entra OIDC + RBAC + worked example

Branch: `feat/entra-rbac`

### 4.1 Scope

- Containerized OIDC mock added to compose.
- Backend: OIDC middleware, cookie auth, RBAC tables, permission registry, authorization policies, admin endpoints, JIT provisioning, production safety rail.
- Both SPAs: `useAuth()` + three gating primitives + ProtectedRoute (or middleware-equivalent).
- `internal/`: worked-example item detail screen + admin user/role screens + persona debug strip.
- `frontend/`: one example screen using the primitives (cross-framework consistency proof).
- Test personas + dev-only role seed.
- Smoke updated to log in via mock-OIDC.
- `docs/auth.md` added.

### 4.2 Backend changes

**New files:**
- `backend/src/ProjectTemplate.Api/Auth/`
  - `OidcConfiguration.cs` — config binding
  - `AuthEndpoints.cs` — `/api/auth/login`, `/logout`, `/config`, `/me`, `/test/personas`
  - `JitProvisioningMiddleware.cs` — creates/updates `Users` row on each authenticated request
  - `PermissionAuthorizationHandler.cs` — resolves user permissions from DB; caches in claims for the session
  - `PermissionRequirement.cs` — IAuthorizationRequirement
  - `PermissionPolicyProvider.cs` — dynamic policy resolution from `RequireAuthorization("items:write")`
  - `StartupGuards.cs` — production safety rail (refuses dev issuer in prod env)
- `backend/src/ProjectTemplate.Domain/Auth/`
  - `User.cs`, `Role.cs`, `Permission.cs`, `UserRole.cs`, `RolePermission.cs` — record types
  - `IUserRepository.cs`, `IRoleRepository.cs`, `IPermissionRegistry.cs`
  - `IItemAuthorizationPolicy.cs` — `CanEdit`, `CanDelete`, `CanApprove`
- `backend/src/ProjectTemplate.Infrastructure/Auth/`
  - `EfUserRepository.cs`, `EfRoleRepository.cs`
  - `PermissionRegistry.cs` — code-defined keys, reconciled to DB at startup
  - `ItemAuthorizationPolicy.cs` — concrete impl
- `backend/src/ProjectTemplate.Api/Endpoints/Admin/`
  - `UsersEndpoints.cs`, `RolesEndpoints.cs`, `PermissionsEndpoints.cs`
- `backend/src/ProjectTemplate.Infrastructure/Migrations/<timestamp>_AddAuthTables.cs`
- `backend/src/ProjectTemplate.Infrastructure/Seed/DevPersonaSeeder.cs` — runs only when issuer host is dev

**Modified:**
- `backend/src/ProjectTemplate.Api/Program.cs` — OIDC + cookie auth registration, permission policies, JIT middleware, startup guard
- `backend/src/ProjectTemplate.Api/Endpoints/ItemsEndpoints.cs` — `RequireAuthorization("items:read")` etc.; DTO projection + `_permissions` shaping per user
- `backend/src/ProjectTemplate.Infrastructure/AppDbContext.cs` — new entity sets + relationships
- `backend/Directory.Packages.props` — adds `Microsoft.AspNetCore.Authentication.OpenIdConnect`, `Microsoft.AspNetCore.Authentication.Cookies`

### 4.3 Frontend (Vue) changes

- `frontend/src/lib/auth.ts` — Pinia store wrapping `/api/auth/me`; `useAuth()` composable; `can()` helper
- `frontend/src/components/auth/RequirePermission.vue`
- `frontend/src/components/auth/DisableWithoutPermission.vue`
- `frontend/src/components/auth/ReadOnlyWithoutPermission.vue`
- `frontend/src/views/LoginView.vue` — render varies by `provider` (Microsoft button vs persona picker)
- `frontend/src/router/index.ts` — `beforeEach` guard
- `frontend/src/views/ItemDetailView.vue` — one example screen exercising the primitives

### 4.4 Internal (Next.js) changes

- `internal/src/middleware.ts` — Next.js middleware: redirect unauthenticated requests to `/login` at the edge before pages render
- `internal/src/lib/auth.tsx` — `'use client'` `AuthProvider` + `useAuth()` (react-query under the hood); reads `/api/auth/me`
- `internal/src/components/auth/RequirePermission.tsx` — `'use client'`
- `internal/src/components/auth/DisableWithoutPermission.tsx` — `'use client'`
- `internal/src/components/auth/ReadOnlyWithoutPermission.tsx` — `'use client'`
- `internal/src/app/login/page.tsx` — render varies by `/api/auth/config` provider; client component
- `internal/src/app/items/[id]/page.tsx` — RSC shell that fetches the item server-side (forwarding the cookie); renders `<ItemDetailClient />` — **worked example** (§4.5)
- `internal/src/app/items/[id]/_components/ItemDetailClient.tsx` — `'use client'`; consumes the gating primitives
- `internal/src/app/admin/users/page.tsx` — list, search, role assignment
- `internal/src/app/admin/roles/page.tsx` — list, create, edit, attach permissions
- `internal/src/components/PersonaDebugStrip.tsx` — `'use client'`; dev-only render diff (returns `null` when `process.env.NODE_ENV === 'production'`)

**Server vs Client Components.** Pages (`page.tsx`) are React Server Components by default — they fetch data server-side with the cookie forwarded via `next/headers`. All gating primitives, the `useAuth()` hook, and any component using react-query are `'use client'`. The worked-example page is a thin RSC: it fetches `item` server-side (so the *initial* DTO projection happens on the server, before HTML reaches the browser) and hands the data to `<ItemDetailClient />` which owns the gating logic. This means the persona-shaped DTO is never even sent to the wrong client — the SSR HTML is already shaped correctly for the requesting user.

### 4.5 Worked example: `internal/src/app/items/[id]/page.tsx` (+ `ItemDetailClient.tsx`)

```
+-----------------------------------------------------------+
| <PersonaDebugStrip />   // dev-only; lists user's perms,  |
|                         // every gated control on screen, |
|                         // and shows what each persona    |
|                         // would render for comparison    |
+-----------------------------------------------------------+
| Item: {item.title}                       Action bar:      |
|                                                           |
|       <RequirePermission p="items:write">                 |
|         <Button>Edit</Button>                             |
|       </RequirePermission>                                |
|                                                           |
|       <DisableWithoutPermission                           |
|         p="items:delete"                                  |
|         resourcePermission={item._permissions.delete}>    |
|         <Button>Delete</Button>                           |
|       </DisableWithoutPermission>                         |
|                                                           |
|       <ReadOnlyWithoutPermission                          |
|         p="items:approve"                                 |
|         resourcePermission={item._permissions.approve}>   |
|         <Switch>Approved</Switch>                         |
|       </ReadOnlyWithoutPermission>                        |
+-----------------------------------------------------------+
| Body                                                      |
|                                                           |
|   <ReadOnlyWithoutPermission p="items:write">             |
|     <Input  label="Title"        value={item.title} />    |
|     <Textarea label="Description" value={item.description}/> |
|   </ReadOnlyWithoutPermission>                            |
|                                                           |
|   <DisableWithoutPermission p="items:write">              |
|     <Button>Save</Button>                                 |
|   </DisableWithoutPermission>                             |
+-----+-----------------------------------------------------+
|     | Sidebar                                             |
|     |                                                     |
|     | <RequirePermission p="audit:read">                  |
|     |   <AuditTrailPanel notes={item.auditNotes} />       |
|     | </RequirePermission>                                |
+-----+-----------------------------------------------------+
```

`auditNotes` is **only present in the response payload** when the user has `audit:read` (server-side projection). The `<RequirePermission>` wrapper is belt-and-suspenders.

The RSC shell (`page.tsx`) fetches `item` via the .NET API with the cookie forwarded; the persona-shaped DTO is rendered into HTML on the server. `ItemDetailClient.tsx` receives the already-shaped item as a prop and consumes the gating primitives for interactivity.

### 4.6 Persona render matrix — same `/items/:id` URL

This matrix is the **canonical test oracle**. Backend integration tests, frontend unit tests, and e2e tests all assert against it.

| Element | Viewer | Editor | Approver | Auditor | Superuser |
|---|---|---|---|---|---|
| Page loads (200) | yes | yes | yes | yes | yes |
| Title field | readonly | editable | readonly | readonly | editable |
| Description field | readonly | editable | readonly | readonly | editable |
| Edit button | hidden | visible | hidden | hidden | visible |
| Delete button | disabled | disabled | disabled | disabled | enabled |
| Approve toggle | readonly | readonly | enabled | readonly | enabled |
| Save button | disabled | enabled | disabled | disabled | enabled |
| Audit panel | hidden | hidden | hidden | visible | visible |
| `auditNotes` in payload | absent | absent | absent | present | present |
| `internalNotes` in payload | absent | absent | absent | absent | present |
| `_permissions.edit` | false | true | false | false | true |
| `_permissions.delete` | false | false | false | false | true |
| `_permissions.approve` | false | false | true | false | true |

### 4.7 Acceptance criteria — PR 2

**Backend**
- [ ] OIDC middleware wired; `OIDC_ISSUER`, `OIDC_CLIENT_ID`, `OIDC_CLIENT_SECRET` consumed
- [ ] Cookie auth issued on successful OIDC callback; cookie name `pt_session`; httpOnly + SameSite=Lax + signed
- [ ] `/api/auth/me` returns user with `roles[]` and `permissions[]`
- [ ] `/api/auth/config` returns `{ provider }`
- [ ] All `/api/items*` endpoints require auth; correct permission per verb
- [ ] Item DTOs include `_permissions` computed per user per resource
- [ ] Item DTOs project fields based on permissions (`auditNotes` hidden without `audit:read`; `internalNotes` hidden without superuser)
- [ ] `/api/admin/*` endpoints exist; enforce `users:manage` / `roles:manage`
- [ ] EF migration creates the 5 new tables; idempotent on re-run
- [ ] `IPermissionRegistry` reconciles permission keys to DB rows at startup; deactivated keys flip `is_active=false`
- [ ] Startup guard fails fast when `OIDC_ISSUER` host is private/loopback **and** `ASPNETCORE_ENVIRONMENT=Production`

**Compose / mock OIDC**
- [ ] `oidc` service in `docker-compose.yml`; mock-oauth2-server starts; discovery reachable from `api`
- [ ] `infra/dev/mock-oidc.json` defines 5 personas
- [ ] Dev seed populates `Test*` roles and assigns to personas; runs only against dev issuer

**Frontend (Vue)**
- [ ] `useAuth()` composable + `can()`
- [ ] All three primitive components
- [ ] `LoginView`; router guard; redirect to `/login` on 401
- [ ] One example screen using the primitives

**Internal (Next.js)**
- [ ] `useAuth()` hook + `AuthProvider`
- [ ] All three primitive components
- [ ] `middleware.ts` redirects unauthenticated requests to `/login`
- [ ] Login page handles both providers based on `/api/auth/config`
- [ ] Worked-example item detail screen renders per §4.5; RSC shell + Client component split as described
- [ ] Sidebar nav auto-filters by permission
- [ ] Admin users + roles screens functional
- [ ] PersonaDebugStrip renders only when `process.env.NODE_ENV !== 'production'`

**Smoke**
- [ ] `scripts/smoke.sh` logs in via mock-OIDC, performs CRUD with cookie, logs out
- [ ] Smoke verifies 401 when no cookie present
- [ ] Smoke verifies persona render diff at the API level (Viewer vs Auditor sees different DTOs for the same item)

**Docs**
- [ ] `docs/auth.md` covers: OIDC setup (Entra + dev mock), env var reference, RBAC model, permission registration, primitives usage, worked-example walkthrough, persona matrix, screenshots
- [ ] `CLAUDE.md` updated with auth conventions
- [ ] `README.md` quick-start notes mock-OIDC + persona picker

### 4.8 Test plan — PR 2

#### 4.8.1 Backend

| Layer | What | Where | Pass criterion |
|---|---|---|---|
| Unit | `IPermissionRegistry` reconciliation | `backend/tests/Auth/PermissionRegistryTests.cs` | New keys inserted; deleted keys deactivated; idempotent |
| Unit | `IItemAuthorizationPolicy.CanEdit` | `backend/tests/Auth/ItemAuthorizationPolicyTests.cs` | xUnit theory: persona × ownership state → expected boolean |
| Unit | DTO projection | `backend/tests/Items/ItemProjectionTests.cs` | `auditNotes` present iff `audit:read`; `_permissions` matches policy decisions |
| Integration | OIDC login flow | `backend/tests/Auth/OidcLoginIntegrationTests.cs` | `WebApplicationFactory` + ephemeral mock-oauth2-server (testcontainers); cookie set; `/api/auth/me` reflects persona |
| Integration | JIT provisioning | `backend/tests/Auth/JitProvisioningTests.cs` | First request creates `Users` row; second updates `last_login_at` |
| Integration | Per-persona endpoint authz | `backend/tests/Items/ItemsAuthzTests.cs` | xUnit theory: each persona × each verb → 200 or 403 per matrix |
| Integration | Per-persona DTO shape | `backend/tests/Items/ItemsDtoTests.cs` | Same `GET /api/items/:id` with different cookies returns matrix-correct payloads |
| Integration | Admin endpoints | `backend/tests/Admin/UsersEndpointsTests.cs`, `RolesEndpointsTests.cs` | CRUD round-trips; non-admin → 403; orphaned-role-delete → 409 |
| Integration | Production safety rail | `backend/tests/Auth/StartupGuardTests.cs` | Booting with prod env + dev-host issuer fails with specific exception type |

#### 4.8.2 Frontend (Vue)

| Layer | What | Where | Pass criterion |
|---|---|---|---|
| Unit | `useAuth` composable | `frontend/src/__tests__/auth.test.ts` | Renders user from mocked `/me`; `can()` returns expected booleans across personas |
| Unit | Each primitive | `frontend/src/__tests__/primitives.test.ts` | Renders / hides / disables / readonlies per props |
| Integration | Router guard | `frontend/src/__tests__/router.test.ts` | Redirects to `/login` on 401 |
| Integration | Example screen — persona matrix | `frontend/src/__tests__/item-detail.test.ts` | For each persona, mounts page with mocked API; asserts visible/disabled/readonly per matrix |

#### 4.8.3 Internal (Next.js)

| Layer | What | Where | Pass criterion |
|---|---|---|---|
| Unit | `useAuth` hook | `internal/src/__tests__/auth.test.tsx` | RTL + react-query test wrapper; `can()` correct |
| Unit | Each primitive | `internal/src/__tests__/primitives.test.tsx` | Renders / disabled / readonly variants asserted |
| Integration | Worked-example client component — persona matrix | `internal/src/__tests__/items-detail.test.tsx` | Parameterised over 5 personas; mounts `<ItemDetailClient />` with mocked item DTO; asserts §4.6 matrix exactly |
| Integration | Admin screens | `internal/src/__tests__/admin-users.test.tsx`, `admin-roles.test.tsx` | Role assignment flows render; correct endpoints called |
| Integration | Middleware redirect | `internal/src/__tests__/middleware.test.ts` | `middleware()` returns 302 to `/login` when no cookie; passes through when cookie present |

#### 4.8.4 E2E (Playwright)

| Test | Where | Pass criterion |
|---|---|---|
| `loginAs(persona)` helper | `e2e/fixtures/auth.ts` | Drives mock-OIDC headlessly via `login_hint`; returns authenticated context |
| Auth flow | `e2e/tests/auth.spec.ts` | Login as Editor → editable form; logout clears session; subsequent `/api/auth/me` is 401 |
| **Persona render matrix** | `e2e/tests/rbac-persona-matrix.spec.ts` | Parameterised over 5 personas; navigates to the same item; asserts §4.6 matrix exactly via the live UI |
| Admin user/role flow | `e2e/tests/admin-flows.spec.ts` | Superuser creates a role, assigns it to a user; that user reloads and gains the new permission |
| Negative cases | `e2e/tests/rbac-negative.spec.ts` | Direct API hits without cookie → 401; with insufficient perms → 403; SPA shows splash on insufficient perms |
| Cross-framework consistency | `e2e/tests/rbac-cross-framework.spec.ts` | Same persona in `frontend/` (Vue) and `internal/` (Next.js) sees identical effective rules on the shared example screen |

#### 4.8.5 Smoke

`scripts/smoke.sh` extended to run, in order:

1. `docker compose up --build` (now includes `oidc`)
2. Wait for `oidc`, `api`, `frontend`, `internal` health checks
3. Authenticate as `superuser@test.local` via mock-OIDC code flow (curl + cookie jar; mock supports non-interactive `login_hint`)
4. CRUD round-trip on `/api/items` with cookie — must return 200s
5. Same CRUD without cookie — must return 401
6. Authenticate as `viewer@test.local`; `GET /api/items/:id` → DTO without `auditNotes` and `_permissions.delete = false`
7. Authenticate as `auditor@test.local`; same `GET` → DTO with `auditNotes` present
8. Logout; `GET /api/auth/me` → 401
9. `docker compose down -v`

This proves end-to-end: mock IdP, backend OIDC pipeline, cookie auth, DTO projection, persona variance, both SPAs serving HTML.

#### 4.8.6 Production-path verification

- Optional CI job `.github/workflows/entra-smoke.yml` — opt-in, requires repo secrets `ENTRA_TENANT_ID`, `ENTRA_CLIENT_ID`, `ENTRA_CLIENT_SECRET` — points the backend at a real Entra tenant and runs a minimal headless login. Skipped by default. Documented as the way to verify Entra integration before deploying.
- No automated test runs against a real Entra tenant in PRs (license/tenant cost). The same code path is exercised in dev via mock-OIDC, so OIDC regressions surface there.

### 4.9 Rollout / migration

- DB migration is additive (5 new tables). Existing `Items` data unaffected.
- Existing API consumers without auth break. Intentional and headline. Documented in `docs/auth.md` and the PR description.
- Rollback = revert the merge + run the `Down` migration (drops the 5 new tables). No data loss in `Items`.

---

## 5. Open questions / decisions to confirm before implementation starts

1. **Next.js output mode**: `output: "standalone"` (proposed) — produces a self-contained Node bundle. Alternative: `output: "export"` (static) — loses middleware-based auth and edge redirects. **Default: `standalone`.**
2. **Build runtime in CI**: Node 22 in CI (matches the runtime image and Vercel's officially supported path); Bun for local dev only. **Default: split — Bun locally, Node in CI.**
3. **Plan doc fate**: keep this file as design history after implementation, or delete once `docs/auth.md` carries the long-lived content? **Default: keep, mark "implemented" at top once shipped.**
4. **`frontend/` (Vue) RBAC scope in PR 2**: include the Vue primitives + one example screen, or split into a PR 3? **Default: include in PR 2** — proves cross-framework consistency.
5. **Permission key style**: `items:write` (proposed) vs `items.write` vs `Items.Write`. **Default: `items:write`**.
6. **`_permissions` field name**: leading underscore signals metadata. **Default: `_permissions`**.
7. **Cookie name**: **Default: `pt_session`** (custom, grep-friendly) over ASP.NET default `.AspNetCore.Cookies`.
8. **Mock-OIDC image pin**: pin to a specific minor (e.g. `:2.1.10`); Dependabot bumps. **Default: yes, pin specifically.**
9. **Backlog tracking**: capture this plan as one parent task with subtasks per acceptance criterion via `backlog task create`? **Default: yes**, after this plan is approved.

## 6. Out of scope (this work, future PRs)

- Multi-tenant isolation
- Group-based authorization (Entra groups → roles)
- Self-service role requests
- Audit log of authorization decisions (separate concern from `audit:read`)
- API rate limiting per role
- SCIM provisioning
- Migrating `frontend/` to React/Next.js or `internal/` to anything else
- Migrating the .NET backend to Bun/Node — see §7 for the contingency design

---

## 7. Plan B — Bun/Node backend (contingency design, not implemented)

This section documents an alternative backend stack we may move to in the future. **Nothing in this section is implemented in PR 1 or PR 2.** It exists so that:

- The .NET API contract is designed with portability in mind.
- A future migration can happen without re-litigating the design.
- Operators evaluating the template can see a clear path forward if they don't want to maintain .NET.

### 7.1 Why we'd consider switching

- Language/toolchain consistency across stack (TypeScript everywhere — same lang as `frontend/` and `internal/`).
- Smaller container images (Bun ~70 MB vs .NET ASP.NET ~200 MB).
- Faster cold start, lower memory baseline.
- Simpler hiring profile for full-stack TS teams.

### 7.2 Why we're keeping .NET for now

- .NET 10 is the current target and is well-tested in the template.
- The `Items` worked example is already wired in C#.
- ASP.NET Core's authorization pipeline (`[Authorize("perm")]` + policy providers) is mature; reimplementing it cleanly in Hono takes work.
- The template's value is in the *patterns*, not the runtime — switching is a line-by-line port, not a redesign.

### 7.3 Proposed Plan B stack

| Concern | .NET (current) | Bun (Plan B) |
|---|---|---|
| Runtime | .NET 10 | Bun 1.x |
| Framework | ASP.NET Core Minimal API | Hono |
| ORM | EF Core + Npgsql | Drizzle ORM |
| Validation | Data annotations + manual | Zod |
| Auth | `Microsoft.Identity.Web` + cookie auth | `openid-client` + `iron-session` |
| Tests | xUnit + Shouldly + `WebApplicationFactory` | `bun test` + supertest-style helper |
| Migrations | EF Core migrations | Drizzle Kit |
| Container | `mcr.microsoft.com/dotnet/aspnet:10` | `oven/bun:1-slim` |
| Logging | `Microsoft.Extensions.Logging` (source-gen) | `pino` |
| OpenAPI | Swashbuckle | `@hono/zod-openapi` |

### 7.4 What stays portable (designed once, works for both)

- **API contract**: URL shapes, DTO field names, status codes, error format. Codified as an OpenAPI spec — generated from .NET today (Swashbuckle), hand-maintained or generated from Hono later — the spec is the source of truth.
- **DB schema**: tables and migration SQL written to be ORM-agnostic. EF Core migrations today produce SQL Drizzle Kit could replay; Drizzle later produces SQL EF could read. Avoid ORM-specific quirks (no EF shadow properties, no DB-level computed columns owned by an ORM).
- **OIDC flow**: cookie-based, same `/api/auth/*` endpoints, same `OIDC_ISSUER` env var, same cookie name (`pt_session`). The IdP doesn't know which backend is on the other side.
- **RBAC model**: 5 tables, same shape, same `IPermissionRegistry` reconciliation pattern (Drizzle has the same idiom as EF).
- **Authorization policy**: an interface like `IItemAuthorizationPolicy.canEdit(user, item)` exists in both languages with the same signature. Drives both the endpoint guard and the `_permissions` projection.

### 7.5 What helps a future swap (worth doing now)

- Adding an OpenAPI spec to PR 2's `docs/auth.md` (or a separate `openapi.yaml`) — both backends can satisfy the same spec, and the SPAs can generate types from it.
- Keeping migrations idempotent and provider-agnostic — easier when written by hand against the actual SQL features used.
- Avoiding C#-specific JSON conventions in DTOs (e.g., `JsonPropertyName` attributes are fine but should mirror what Bun's default JSON serializer would produce).
- Not leaning on .NET-specific features the JS side can't replicate cheaply (e.g., `IAsyncEnumerable<T>` streaming).

### 7.6 What does NOT help (and is explicitly rejected)

- Sharing code between .NET and Bun (no — keep them as parallel implementations).
- Generating one codebase from a schema (no — the cost of the abstraction exceeds the cost of the port).
- Putting "if-Bun-then" branches anywhere (no — pick a runtime and commit; Plan B is a swap, not a multi-runtime build).

### 7.7 If/when we switch (sketch of PR N)

A future PR (call it PR N) would:

1. Implement the API in Bun + Hono with Drizzle, against the same OpenAPI contract.
2. Run both backends side-by-side in CI for one release cycle, asserting parity via the existing integration test suite (rerun against the new backend).
3. Switch the `api` service in `docker-compose.yml` and the Container Apps Terraform module to the new image.
4. Decommission the .NET project after a soak period.

This work is **not** scheduled. It's documented so the design choices we make in PR 2 stay portable.
