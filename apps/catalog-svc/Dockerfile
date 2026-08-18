FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY catalog-svc.csproj .
RUN dotnet restore catalog-svc.csproj
COPY . .
RUN dotnet publish catalog-svc.csproj -c Release -o /app/publish --no-restore

# Chiseled: no shell, no package manager, minimal attack surface. Runs as the
# built-in non-root "app" user (UID 64198) by default — no USER directive
# needed, but set explicitly below for clarity.
FROM mcr.microsoft.com/dotnet/aspnet:8.0-noble-chiseled AS runtime
WORKDIR /app
COPY --from=build /app/publish .
USER app
EXPOSE 8080
ENV ASPNETCORE_URLS=http://+:8080
ENTRYPOINT ["dotnet", "catalog-svc.dll"]
