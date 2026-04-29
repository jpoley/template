FROM oven/bun:1 AS deps
WORKDIR /app

# Enterprise MITM proxy support — see docs/enterprise-proxy.md.
COPY --from=enterprise-ca . /tmp/enterprise-ca/
RUN sh /tmp/enterprise-ca/install-ca-in-image.sh && rm -rf /tmp/enterprise-ca

COPY package.json bun.lock ./
# Strict — keep image install behavior identical to CI. If the lockfile is
# stale, fail loudly so the dev updates and commits it instead of letting
# Docker silently rewrite it.
RUN bun install --frozen-lockfile


FROM oven/bun:1 AS builder
WORKDIR /app

COPY --from=enterprise-ca . /tmp/enterprise-ca/
RUN sh /tmp/enterprise-ca/install-ca-in-image.sh && rm -rf /tmp/enterprise-ca
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt

COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN mkdir -p public

RUN bun run build


FROM node:22-bookworm-slim AS runner
WORKDIR /app

COPY --from=enterprise-ca . /tmp/enterprise-ca/
RUN sh /tmp/enterprise-ca/install-ca-in-image.sh && rm -rf /tmp/enterprise-ca
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt

ENV NODE_ENV=production
ENV PORT=3000
ENV HOSTNAME=0.0.0.0

# Next.js standalone output bundles a minimal server + node_modules subset.
# --chown=node:node lets the runtime user own the files (e.g. for .next/cache).
COPY --from=builder --chown=node:node /app/.next/standalone ./
COPY --from=builder --chown=node:node /app/.next/static ./.next/static
COPY --from=builder --chown=node:node /app/public ./public

USER node
EXPOSE 3000
# node:22 ships fetch built-in; node:22-bookworm-slim has no wget/curl. Use a
# Node-based HTTP probe so the healthcheck doesn't depend on extra packages.
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=5 \
  CMD node -e "fetch('http://127.0.0.1:3000/internal').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node", "server.js"]
