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


# Runtime stage on Bun: Next.js' standalone output is a regular Node-style
# `server.js`, but Bun's Node compatibility runs it directly. This avoids a
# second toolchain (Node) in the runtime image and keeps cold start fast.
FROM oven/bun:1-slim AS runner
WORKDIR /app

COPY --from=enterprise-ca . /tmp/enterprise-ca/
RUN sh /tmp/enterprise-ca/install-ca-in-image.sh && rm -rf /tmp/enterprise-ca
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt

ENV NODE_ENV=production
ENV PORT=3000
ENV HOSTNAME=0.0.0.0

# Next.js standalone output bundles a minimal server + node_modules subset.
# `bun` user (uid/gid 1000) ships in the oven/bun image — chown so the runtime
# user owns the files (Next writes to .next/cache at runtime).
COPY --from=builder --chown=bun:bun /app/.next/standalone ./
COPY --from=builder --chown=bun:bun /app/.next/static ./.next/static
COPY --from=builder --chown=bun:bun /app/public ./public

USER bun
EXPOSE 3000
# bun ships fetch built-in (and supports node-style `process.exit`), so we can
# probe ourselves without curl/wget.
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=5 \
  CMD bun -e "fetch('http://127.0.0.1:3000/internal').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["bun", "server.js"]
