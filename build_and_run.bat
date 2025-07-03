@echo off
echo Building and starting fixed container...

docker-compose -f docker-compose.fixed.yml build
docker-compose -f docker-compose.fixed.yml up -d

echo.
echo Container status:
docker ps -a | findstr pia-wg-generator

echo.
echo Container logs:
docker logs pia-wg-generator --tail 20

echo.
echo Next steps:
echo 1. To check cron job: docker exec pia-wg-generator crontab -l
echo 2. To manually trigger update: docker exec pia-wg-generator sh -c "cd /app && ./pia-wg-cfg-generator.sh && cp -v /app/configs/*.conf \$CONFIG_DIR/ 2>/dev/null || echo 'No new configs to copy'"
echo 3. To view container logs: docker logs pia-wg-generator
