# Port conflicts — troubleshooting guide

When you run `./rebuild.sh` (or `docker compose up`) and a service fails to start with something like:

```
Error response from daemon: ... bind: address already in use
```

…another program on your computer is already using that port. This guide walks you through finding it and fixing it, without needing to know Docker internals.

---

## 1. What ports does this project use?

Every service has **two ports**: one inside its container (fixed, internal) and one on your laptop (the "host" port, which is what you type into a browser). Only the host ports can conflict with other software on your machine.

| Service | Host port | Container port | What it is |
| --- | --- | --- | --- |
| Frontend | `6173` | `80` | The public website (nginx) |
| Admin | `6174` | `80` | The internal admin UI (nginx) |
| Backend API | `6180` | `8080` | The .NET API |
| PostgreSQL | `6432` | `5432` | PostgreSQL 16 (only when `postgres` profile active — default) |
| SQL Server | `6433` | `1433` | SQL Server 2022 (only when `sqlserver` profile active) |

Only one of `postgres`/`sqlserver` is active at a time — they're mutually exclusive compose profiles. See [`database-providers.md`](../database-providers.md).

**Rule of thumb:** if an error message says "already in use", it's the host port (the left-hand number) that's the problem. Container ports are private to Docker and can't conflict with anything on your laptop.

---

## 2. Find what's using the port

Open a terminal and run one of these, replacing `6180` with whichever port is in trouble:

### macOS / Linux

```bash
lsof -iTCP:6180 -sTCP:LISTEN
```

You'll see output like:

```
COMMAND    PID  USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
java     40213   me   52u  IPv6 0x...             0t0  TCP *:6180 (LISTEN)
```

The `COMMAND` column tells you **which program** is using it. The `PID` is a number you can use to look it up or stop it.

### Windows (PowerShell)

```powershell
Get-NetTCPConnection -LocalPort 6180 -State Listen | Select-Object OwningProcess
Get-Process -Id <PID from above>
```

---

## 3. What's probably using it

A few common culprits:

| You see this | It's probably |
| --- | --- |
| `docker` or `com.docker.backend` | Another docker-compose project you forgot about |
| `containerd-shim`, `kube-apiserver`, `kind` | A local Kubernetes cluster (kind, minikube, k3d, Docker Desktop's Kubernetes) |
| `node`, `bun`, `vite` | A dev server from another project |
| `java` | Jenkins, Tomcat, a Spring Boot app, or an IDE |
| `python` | A local Flask/FastAPI/Django server |
| `Orb`, `colima`, `rancher` | An alternative Docker runtime |
| `ControlCe` on macOS, port `5000` or `7000` | Apple's AirPlay Receiver — turn it off in **System Settings → General → AirDrop & Handoff** |

---

## 4. Fix it: three options, in order of simplicity

### Option A — stop the other thing

If it's safe to stop (e.g. a project you're not actively working on):

```bash
# macOS / Linux, using the PID from step 2
kill <PID>

# Or if it's a Docker container, find its name and:
docker ps
docker stop <container-name>
```

Then re-run `./rebuild.sh`.

### Option B — change our port (don't touch the other program)

If you can't or don't want to stop the other program, we move **our** port instead. Edit `docker-compose.yml`. Find the `ports:` line for the service in trouble and change the **left-hand number** (the host port) to something unused, say `7180` instead of `6180`:

```yaml
  backend:
    ports:
      - "7180:8080"   # was 6180:8080
```

> Only change the **left** number. The right side is the container's internal port and must stay the same.

You also need to update a few other places so everything agrees on the new port. Use your editor's find-and-replace across these files:

- `docker-compose.yml` — the `ports:` line you just changed, and the `Cors__Origins__*` lines if you changed the frontend/admin ports
- `frontend/vite.config.ts` and `admin/vite.config.ts` — `port:` and the `proxy` target
- `frontend/package.json` and `admin/package.json` — the `preview` script
- `backend/src/ProjectTemplate.Api/appsettings.json` — `Cors.Origins`
- `backend/src/ProjectTemplate.Api/Properties/launchSettings.json` — `applicationUrl`
- `rebuild.sh` — the port table at the end
- `.devcontainer/devcontainer.json` — `forwardPorts` and `portsAttributes`
- `e2e/playwright.config.ts` and `e2e/tests/*.spec.ts` — the `*_PORT` / URL constants
- `README.md` — the URL table
- This file

Then `./rebuild.sh` again.

### Option C — just check nothing is hanging around from us

Sometimes the conflict is a previous run of this same project that didn't shut down cleanly:

```bash
docker ps -a | grep projecttemplate
docker compose down --remove-orphans
./rebuild.sh
```

---

## 5. Still stuck?

Attach the output of these three commands when asking for help — they'll show exactly what's conflicting and why:

```bash
docker compose ps
docker ps --format "table {{.Names}}\t{{.Ports}}"
lsof -iTCP -sTCP:LISTEN | grep -E '6173|6174|6180|6432|6433'
```
