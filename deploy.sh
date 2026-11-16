#!/usr/bin/env bash
# Release deployment for the existing shopdemo Compose project.
# Run on the Ubuntu VPS from the directory containing both Compose files.
set -Eeuo pipefail
umask 077

cd "$(dirname "$0")"

if [[ $# -ne 1 ]]; then
  echo "Usage: bash deploy-with-migrations.sh ghcr.io/OWNER/shop-api:TAG" >&2
  exit 2
fi

export SHOP_IMAGE="$1"
compose=(docker compose -f compose.yaml -f compose.prod.yaml)

# A second deployment (GitHub Actions or a human) must not overlap this one.
command -v flock >/dev/null || { echo 'flock is required (util-linux)' >&2; exit 1; }
exec 9>.shopdemo-deploy.lock
flock -n 9 || { echo 'Another deployment is already running' >&2; exit 1; }

echo "Deploying $SHOP_IMAGE"
"${compose[@]}" config --quiet

# Existing VPS installations are expected to have a running database.
# Do not recreate / reinitialize it as a side effect of a release.
if [[ -z "$("${compose[@]}" ps -q db)" ]]; then
  echo 'Database container is not running; investigate before deploying.' >&2
  exit 1
fi
"${compose[@]}" exec -T db pg_isready -h 127.0.0.1 -U shop -d shop >/dev/null || {
  echo 'PostgreSQL is not ready; deployment stopped.' >&2
  exit 1
}

# Prevent the classic production mistake: running EF InitialCreate on a
# SQL-initialized products table that has no EF migration history.
state="$("${compose[@]}" exec -T db psql -X -v ON_ERROR_STOP=1 -U shop -d shop -At <<'SQL'
SELECT (to_regclass('public.products') IS NOT NULL)::int::text
       || ':' ||
       (to_regclass('public."__EFMigrationsHistory"') IS NOT NULL)::int::text;
SQL
)"

case "$state" in
  '1:0')
    echo 'STOP: products exists but __EFMigrationsHistory does not.' >&2
    echo 'Back up, verify the schema, and baseline InitialCreate ONCE before deploying.' >&2
    exit 1
    ;;
  '0:0')
    echo 'Database has neither products nor EF history; EF can initialize a genuinely fresh database.'
    ;;
  '1:1')
    initial_count="$("${compose[@]}" exec -T db psql -X -v ON_ERROR_STOP=1 -U shop -d shop -At <<'SQL'
SELECT COUNT(*) FROM "__EFMigrationsHistory"
WHERE "MigrationId" LIKE '%_InitialCreate';
SQL
)"
    if [[ "$initial_count" != '1' ]]; then
      echo 'STOP: InitialCreate is not recorded exactly once in EF history.' >&2
      echo 'Review production migration history before proceeding.' >&2
      exit 1
    fi
    ;;
  *)
    echo "STOP: unexpected database schema state ($state). Inspect DB manually." >&2
    exit 1
    ;;
esac

# Preserve a local point-in-time logical backup before the schema change.
# This is NOT a replacement for tested off-server backups / PITR.
mkdir -p backups
backup="backups/shop-before-$(date -u +%Y%m%dT%H%M%SZ).dump"
echo "Backing up PostgreSQL to $backup"
if ! "${compose[@]}" exec -T db pg_dump -U shop -d shop -Fc > "$backup"; then
  rm -f "$backup"
  echo 'Backup failed. No migration or API update attempted.' >&2
  exit 1
fi

# Pull only the new API image. Do not replace the current API yet.
"${compose[@]}" pull api

# One-off container using the NEW image, EXISTING DB/network and secret.
# A nonzero migration exit code stops the script before the API is replaced.
echo 'Applying EF Core migrations with a one-off container...'
"${compose[@]}" run --rm --no-deps -T api --migrate

echo 'Migrations succeeded; updating API replicas.'
# Derive current replica count to avoid accidentally scaling 3 replicas to 1.
if [[ -z "${API_REPLICAS:-}" ]]; then
  API_REPLICAS="$("${compose[@]}" ps -q api | wc -l | tr -d '[:space:]')"
  [[ "$API_REPLICAS" -gt 0 ]] || API_REPLICAS=1
fi
if ! [[ "$API_REPLICAS" =~ ^[1-9][0-9]*$ ]]; then
  echo 'API_REPLICAS must be a positive integer' >&2
  exit 1
fi
"${compose[@]}" up -d --no-deps --no-build --pull never \
  --scale "api=$API_REPLICAS" api

# Preserve the Nginx refresh behavior from the original deploy.sh.
# If Nginx is configured for dynamic upstream DNS, this may be unnecessary.
"${compose[@]}" up -d --no-deps --no-build --force-recreate nginx

echo 'Checking API readiness through the existing production HTTP endpoint...'
HEALTH_URL="${HEALTH_URL:-http://127.0.0.1/health/ready}"
for i in {1..30}; do
  if curl -fsS --max-time 5 "$HEALTH_URL" >/dev/null; then
    # Keep any existing .env settings instead of overwriting the entire file.
    tmp="$(mktemp ./.env.new.XXXXXX)"
    if [[ -f .env ]]; then
      awk -v image="$SHOP_IMAGE" '
        BEGIN { found=0 }
        /^SHOP_IMAGE=/ { if (!found) { print "SHOP_IMAGE=" image; found=1 }; next }
        { print }
        END { if (!found) print "SHOP_IMAGE=" image }
      ' .env > "$tmp"
    else
      printf 'SHOP_IMAGE=%s\n' "$SHOP_IMAGE" > "$tmp"
    fi
    chmod 600 "$tmp"
    mv -f "$tmp" .env
    echo "Deployment successful: $SHOP_IMAGE (replicas=$API_REPLICAS)"
    "${compose[@]}" ps
    exit 0
  fi
  sleep 2
done

echo 'Deployment NOT verified: readiness failed after replacing API.' >&2
echo 'The database may already be migrated; do NOT blindly run a Down migration.' >&2
echo 'Investigate before deciding whether to restore the previous compatible image.' >&2
"${compose[@]}" ps -a
"${compose[@]}" logs --tail=80 --no-color api nginx db
exit 1
