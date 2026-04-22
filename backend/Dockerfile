# --- build stage --------------------------------------------------------
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY global.json Directory.Build.props ./
COPY Backend.sln ./
COPY src/ProjectTemplate.Domain/ProjectTemplate.Domain.csproj src/ProjectTemplate.Domain/
COPY src/ProjectTemplate.Infrastructure/ProjectTemplate.Infrastructure.csproj src/ProjectTemplate.Infrastructure/
COPY src/ProjectTemplate.Api/ProjectTemplate.Api.csproj src/ProjectTemplate.Api/
COPY tests/ProjectTemplate.Api.Tests/ProjectTemplate.Api.Tests.csproj tests/ProjectTemplate.Api.Tests/

RUN dotnet restore src/ProjectTemplate.Api/ProjectTemplate.Api.csproj

COPY . .
RUN dotnet publish src/ProjectTemplate.Api/ProjectTemplate.Api.csproj \
    -c Release \
    -o /app/publish \
    /p:UseAppHost=false

# --- runtime stage ------------------------------------------------------
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
COPY --from=build /app/publish .

ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080

USER $APP_UID

HEALTHCHECK --interval=30s --timeout=3s \
  CMD wget -qO- http://localhost:8080/api/health || exit 1

ENTRYPOINT ["dotnet", "ProjectTemplate.Api.dll"]
