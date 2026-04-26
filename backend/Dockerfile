# --- build stage --------------------------------------------------------
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
ARG BUILD_CONFIG=Release
WORKDIR /src

# Enterprise MITM proxy support — see docs/enterprise-proxy.md. The named
# `enterprise-ca` build context is supplied by docker-compose.yml; the install
# script no-ops when no cert is staged. Doing this before `dotnet restore`
# means NuGet sees the enterprise root.
COPY --from=enterprise-ca . /tmp/enterprise-ca/
RUN sh /tmp/enterprise-ca/install-ca-in-image.sh && rm -rf /tmp/enterprise-ca

COPY global.json Directory.Build.props ./
COPY Backend.sln ./
COPY src/ProjectTemplate.Domain/ProjectTemplate.Domain.csproj src/ProjectTemplate.Domain/
COPY src/ProjectTemplate.Infrastructure/ProjectTemplate.Infrastructure.csproj src/ProjectTemplate.Infrastructure/
COPY src/ProjectTemplate.Api/ProjectTemplate.Api.csproj src/ProjectTemplate.Api/
COPY tests/ProjectTemplate.Api.Tests/ProjectTemplate.Api.Tests.csproj tests/ProjectTemplate.Api.Tests/

RUN dotnet restore src/ProjectTemplate.Api/ProjectTemplate.Api.csproj

COPY . .
RUN dotnet publish src/ProjectTemplate.Api/ProjectTemplate.Api.csproj \
    -c $BUILD_CONFIG \
    -o /app/publish \
    /p:UseAppHost=false

# --- runtime stage (production) -----------------------------------------
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app

# curl for HEALTHCHECK (aspnet base image has neither curl nor wget).
RUN apt-get update \
  && apt-get install -y --no-install-recommends curl \
  && rm -rf /var/lib/apt/lists/*

# Enterprise MITM proxy support — see docs/enterprise-proxy.md.
COPY --from=enterprise-ca . /tmp/enterprise-ca/
RUN sh /tmp/enterprise-ca/install-ca-in-image.sh && rm -rf /tmp/enterprise-ca

COPY --from=build /app/publish .

ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080

USER $APP_UID

HEALTHCHECK --interval=30s --timeout=3s \
  CMD curl -fsS http://127.0.0.1:8080/api/health || exit 1

ENTRYPOINT ["dotnet", "ProjectTemplate.Api.dll"]

# --- debug stage (local dev only) ---------------------------------------
# Layers Microsoft's vsdbg debugger on top of the runtime image so VS Code /
# Rider can attach to the running .NET process via `docker exec`. Pair with
# BUILD_CONFIG=Debug at build time so PDBs + unoptimized IL ship with the app.
FROM runtime AS debug
USER root
RUN apt-get update \
  && apt-get install -y --no-install-recommends unzip procps \
  && rm -rf /var/lib/apt/lists/* \
  && curl -sSL https://aka.ms/getvsdbgsh -o /tmp/getvsdbg.sh \
  && bash /tmp/getvsdbg.sh -v latest -l /vsdbg \
  && rm /tmp/getvsdbg.sh \
  && chmod -R a+r /vsdbg
USER $APP_UID
