# Enterprise CA bundle

Drop your enterprise root CA here as `enterprise-ca.crt` (PEM format) when this
repo is being built or run behind a TLS-intercepting proxy (Zscaler, Netskope,
Palo Alto Prisma Access, on-prem Squid+MITM, etc.).

A non-empty `certs/enterprise-ca.crt` is the **single toggle** for the whole
template:

- non-empty → host install scripts, smoke/test runners, Docker builds, and
  runtime containers all trust the cert.
- missing or empty → everything behaves as if no proxy were in the way.

`scripts/enterprise-cert.sh enable` writes `enterprise-ca.crt` *and* generates
a richer `enterprise-ca.env` alongside it (covers `AWS_CA_BUNDLE`,
`REQUESTS_CA_BUNDLE`, `GIT_SSL_CAINFO`, etc. — sourced when present). If you
only drop `enterprise-ca.crt` in by hand, the host scripts fall back to
exporting the common subset (`SSL_CERT_FILE`, `NODE_EXTRA_CA_CERTS`,
`CURL_CA_BUNDLE`) directly. Either way the cert file is the switch.

## Quick start

```bash
# install (copies + wires up host trust + persists toggle)
scripts/enterprise-cert.sh enable /path/to/your-corp-root.pem

# inspect
scripts/enterprise-cert.sh status

# remove
scripts/enterprise-cert.sh disable
```

Full reference: [`docs/enterprise-proxy.md`](../docs/enterprise-proxy.md).

## Why it lives here

Git does not track `*.crt` / `*.pem` / `*.key` (see `.gitignore`), but Docker
*does* see this directory as part of the build context. Putting the cert here
lets every Dockerfile `COPY certs/` and run a shared install snippet without
each image having to know the cert's path on the host.
