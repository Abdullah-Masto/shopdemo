
# Stage 1: Build
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build

WORKDIR /src

# Restore dependencies separately for caching
COPY DemoApi.csproj ./
RUN dotnet restore DemoApi.csproj

# Copy source code and publish
COPY . .
RUN dotnet publish DemoApi.csproj \
    -c Release \
    -o /app/publish \
    --no-restore \
    /p:UseAppHost=false

# Stage 2: Runtime
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime

WORKDIR /app
COPY --from=build /app/publish .

ENV ASPNETCORE_HTTP_PORTS=8080

# Run as non-root
USER $APP_UID

EXPOSE 8080
ENTRYPOINT ["dotnet", "DemoApi.dll"]

