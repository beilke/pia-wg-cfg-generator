#!/bin/sh
# check-cron.sh - Check if cron job is correctly installed and functioning

echo "Current crontab:"
docker exec pia-wg-generator crontab -l

echo "\nEnvironment variables in container:"
docker exec pia-wg-generator env | grep -E "PIA_|REGIONS|CONFIG_DIR|DEBUG"

echo "\nLatest logs:"
docker logs pia-wg-generator | tail -n 20
