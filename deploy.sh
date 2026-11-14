
#!/usr/bin/env bash

set -Eeuo pipefail

cd "$(dirname "$0")"

# 1. Require the exact published image.
export SHOP_IMAGE="${1:?Usage: bash deploy.sh IMAGE}"

compose=(docker compose -f compose.yaml -f compose.prod.yaml)

echo "Deploying $SHOP_IMAGE"

# 2. Validate the production Compose configuration.
"${compose[@]}" config --quiet

# 3. Download the tested API image.
"${compose[@]}" pull api

# 4. Start or update the application.
"${compose[@]}" up -d --no-build --pull missing

# 5. Refresh Nginx so it resolves the current API container.
"${compose[@]}" up -d --no-build \
  --no-deps --force-recreate nginx

# 6. Check application readiness.
echo "Waiting for application readiness..."

for i in {1..30}; do
    if curl -fsS --max-time 5 \
        http://127.0.0.1/health/ready; then

        echo
        echo "Deployment successful!"

        # Save the deployed version for future Compose commands.
        printf 'SHOP_IMAGE=%s\n' "$SHOP_IMAGE" > .env

        "${compose[@]}" ps
        exit 0
    fi

    sleep 2
done

echo "Deployment failed: API did not become ready."

"${compose[@]}" ps -a
"${compose[@]}" logs --tail=80 --no-color

exit 1

