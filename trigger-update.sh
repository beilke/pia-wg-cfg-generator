#!/bin/sh
# trigger-update.sh - Manually trigger the update process

echo "Triggering manual update..."
docker exec pia-wg-generator sh -c "cd /app && ./pia-wg-cfg-generator.sh && cp -v /app/configs/*.conf \$CONFIG_DIR/ 2>/dev/null || echo 'No new configs to copy'"

echo "\nLatest logs:"
docker logs pia-wg-generator | tail -n 20
