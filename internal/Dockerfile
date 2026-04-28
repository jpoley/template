FROM oven/bun:1 AS deps
WORKDIR /app

# Enterprise MITM proxy support — see docs/enterprise-proxy.md.
COPY --from=enterprise-ca . /tmp/enterprise-ca/
RUN sh /tmp/enterprise-ca/install-ca-in-image.sh && rm -rf /tmp/enterprise-ca

COPY package.json bun.lock* ./
RUN bun install --frozen-lockfile || bun install


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
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/public ./public

USER node
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://127.0.0.1:3000/ || exit 1
CMD ["node", "server.js"]
