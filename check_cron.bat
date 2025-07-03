@echo off
echo Checking cron configuration in container...

echo Current crontab:
docker exec pia-wg-generator crontab -l

echo.
echo Environment variables in container:
docker exec pia-wg-generator env | findstr /I "PIA_ REGIONS CONFIG_DIR DEBUG"

echo.
echo Latest logs:
docker logs pia-wg-generator --tail 20
