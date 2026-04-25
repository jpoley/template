FROM oven/bun:1 AS build
WORKDIR /app

# Enterprise MITM proxy support — see docs/enterprise-proxy.md.
COPY --from=enterprise-ca . /tmp/enterprise-ca/
RUN sh /tmp/enterprise-ca/install-ca-in-image.sh
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt

COPY package.json bun.lockb* ./
RUN bun install --frozen-lockfile || bun install

COPY . .
RUN bun run build

FROM nginx:1.29-alpine AS runtime
COPY --from=enterprise-ca . /tmp/enterprise-ca/
RUN sh /tmp/enterprise-ca/install-ca-in-image.sh

COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=3s CMD wget -q --spider http://127.0.0.1/ || exit 1
CMD ["nginx", "-g", "daemon off;"]
