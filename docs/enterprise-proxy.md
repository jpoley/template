# Enterprise MITM proxy (Zscaler / Netskope / Prisma Access / Squid)

Corporate networks routinely intercept TLS — every outbound HTTPS connection is
re-signed by a proxy's own root CA. Without that root in your trust store,
*everything* in this template that talks to the network breaks: `bun install`,
`dotnet restore`, `nuget` package fetch, `apt-get update`, `curl`,
`dotnet-install.sh`, `terraform init`, container base-image pulls, the backend's
runtime `HttpClient` calls.

This template ships **one toggle** that fixes all of those at once.

## TL;DR

```bash
# 1. enable
scripts/enterprise-cert.sh enable /path/to/your-corp-root.pem

# 2. apply to your current shell (so install scripts + rebuild see the cert)
eval "$(scripts/enterprise-cert.sh env)"

# 3. rebuild — bakes the cert into every Docker image
./rebuild.sh

# 4. verify (optional)
scripts/enterprise-cert.sh verify https://nuget.org
```

To turn it off:

```bash
scripts/enterprise-cert.sh disable
./rebuild.sh
```

## How the toggle works

The single source of truth is **the file `certs/enterprise-ca.crt`**.

- exists + non-empty → enterprise mode is ON
- missing or empty   → enterprise mode is OFF (default)

That's it. There is no environment flag to set, no compose profile to pick,
no `--enterprise` argument anywhere. You drop the cert in, the rest follows.

```
                          certs/enterprise-ca.crt
                                    │
        ┌───────────────────────────┼─────────────────────────────┐
        │                           │                             │
   host install scripts        Docker images                  host shell
   (via _common.sh)           (via additional_contexts        (via the
        │                       + install-ca-in-image.sh)        env file)
        │                           │                             │
        ▼                           ▼                             ▼
 - SSL_CERT_FILE          - update-ca-certificates       - eval "$(... env)"
 - NODE_EXTRA_CA_CERTS    - cert in /etc/ssl/certs/       - exports the same
 - CURL_CA_BUNDLE         - NODE_EXTRA_CA_CERTS pinned      vars in your shell
 - GIT_SSL_CAINFO           to the merged system bundle
 - REQUESTS_CA_BUNDLE
 - AWS_CA_BUNDLE
```

## What gets covered

| Surface                      | Mechanism                                                |
| ---                          | ---                                                      |
| `curl` in install/*.sh       | `CURL_CA_BUNDLE` from `certs/enterprise-ca.env`          |
| `bun install` / `npm install`| `NODE_EXTRA_CA_CERTS` from `certs/enterprise-ca.env`     |
| `dotnet-install.sh`          | `SSL_CERT_FILE` from `certs/enterprise-ca.env`           |
| `git clone/fetch` (in repo)  | `GIT_SSL_CAINFO` from `certs/enterprise-ca.env`          |
| `terraform init` providers   | system trust + `SSL_CERT_FILE`                           |
| Docker image **build**       | `additional_contexts: enterprise-ca: ./certs` + `update-ca-certificates` |
| Docker image **runtime**     | the cert is baked into `/etc/ssl/certs/ca-certificates.crt` of every image |
| Backend `HttpClient`         | system trust inside the runtime image                    |
| Frontend / admin SSR / build | `NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt` |
| Playwright browser download  | `NODE_EXTRA_CA_CERTS` (`scripts/enterprise-cert.sh env`) |

The **host system trust store** is also offered as an optional convenience —
`scripts/enterprise-cert.sh enable` will run `update-ca-certificates` if you
have passwordless sudo, otherwise it prints the exact command to copy/paste.
This is a nice-to-have for browsers and ad-hoc tools outside this repo, not a
requirement for the template itself.

## File layout

| Path                              | Purpose                                                              |
| ---                               | ---                                                                  |
| `certs/enterprise-ca.crt`         | The cert. **Gitignored.** Created by `enterprise-cert.sh enable`.    |
| `certs/enterprise-ca.env`         | Generated env-export file. Sourced by install scripts.               |
| `certs/install-ca-in-image.sh`    | POSIX-shell installer run inside Docker images. Tracked.             |
| `certs/README.md`                 | Pointer to this doc. Tracked.                                        |
| `scripts/enterprise-cert.sh`      | Host-side `enable` / `disable` / `status` / `env` / `verify`.        |
| `install/_common.sh`              | Sources `certs/enterprise-ca.env` if present.                        |
| `frontend/Dockerfile`, `admin/Dockerfile`, `backend/Dockerfile` | `COPY --from=enterprise-ca ...` + run installer. |
| `docker-compose.yml`              | `additional_contexts: enterprise-ca: ./certs` per service.           |

## Verifying it works

A quick smoke pass that doesn't need a real Zscaler in front of you — generate
a self-signed CA and exercise the toggle:

```bash
# 1. Make a fake enterprise root
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -subj "/CN=fake-corp-root" \
  -keyout /tmp/fake.key -out /tmp/fake.pem >/dev/null 2>&1

# 2. Enable
scripts/enterprise-cert.sh enable /tmp/fake.pem
scripts/enterprise-cert.sh status      # → ENABLED, fingerprint, expiry

# 3. Build with cert baked in
docker compose build frontend admin backend

# 4. Confirm the cert is actually in each runtime image
for c in frontend admin backend; do
  echo "=== $c ==="
  docker compose run --rm --entrypoint sh "$c" -c \
    'awk "/-----BEGIN CERTIFICATE-----/{c++} END{print c\" certs in bundle\"}" /etc/ssl/certs/ca-certificates.crt; \
     test -f /usr/local/share/ca-certificates/enterprise-ca.crt && echo "enterprise-ca.crt present" || echo "MISSING"'
done

# 5. Disable + rebuild + confirm absence
scripts/enterprise-cert.sh disable
docker compose build frontend admin backend
docker compose run --rm --entrypoint sh frontend -c \
  'test -f /usr/local/share/ca-certificates/enterprise-ca.crt && echo "STILL PRESENT (bug)" || echo "absent ✓"'
```

For real-world verification (i.e. you actually are behind Zscaler), the
authoritative test is `scripts/test-all.sh` — every install path, build path,
and runtime call goes through the cert.

## Troubleshooting

**`bun install` still fails with `unable to verify the first certificate`**
— Your shell didn't pick up the env file. Run `eval "$(scripts/enterprise-cert.sh env)"`
or restart the shell after adding the export to your rc.

**Docker build fails on `COPY --from=enterprise-ca`**
— Your docker compose is older than v2.17 (additional_contexts unsupported).
Upgrade Docker Desktop / `docker compose` plugin.

**`update-ca-certificates: command not found` inside an image**
— The base image isn't Debian or Alpine. Extend
`certs/install-ca-in-image.sh` with the matching distro branch.

**`.NET HttpClient` says `the remote certificate was rejected`**
— The cert wasn't picked up at *build* time of the runtime image. Run
`docker compose build --no-cache backend` after enabling.

**`scripts/enterprise-cert.sh enable` says "does not parse as a PEM"**
— You handed it a DER (`.cer`/`.der`) file. Convert first:
`openssl x509 -inform der -in your.cer -out your.pem`.
