# --- build stage --------------------------------------------------------
# BASE_IMAGE defaults to the upstream bun image so this Dockerfile builds
# standalone (slow path: full bun install + CA install). When the build arg
# points at a prebuilt base from Dockerfile.base — locally
# `projecttemplate/frontend-base:local`, in cloud
# `<acr>/template-base/frontend:<ver>` — both steps cache-hit instantly.
ARG BASE_IMAGE=oven/bun:1
FROM ${BASE_IMAGE} AS build
WORKDIR /app

# Enterprise CA install — no-op if the base already installed it.
COPY --from=enterprise-ca . /tmp/enterprise-ca/
RUN sh /tmp/enterprise-ca/install-ca-in-image.sh && rm -rf /tmp/enterprise-ca
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt

# Manifests — same byte content as the base, so layer-cached. With a fresh
# base, this becomes a fast no-op install.
COPY package.json bun.lock* bun.lockb* ./
RUN bun install --frozen-lockfile || bun install

COPY . .
RUN bun run build

# --- runtime stage ------------------------------------------------------
FROM nginx:1.29-alpine AS runtime

COPY --from=enterprise-ca . /tmp/enterprise-ca/
RUN sh /tmp/enterprise-ca/install-ca-in-image.sh && rm -rf /tmp/enterprise-ca

COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s \
  CMD wget -q --spider http://127.0.0.1/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
