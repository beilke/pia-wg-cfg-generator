#!/bin/bash
# Simple script to check container status

container_name="pia-wg-generator"
echo "Checking status of $container_name container..."

# Check if container exists
if ! docker ps -a | grep -q "$container_name"; then
  echo "Container $container_name does not exist."
  exit 1
fi

# Get container status
status=$(docker inspect -f '{{.State.Status}}' "$container_name")
health_status=$(docker inspect -f '{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "Not configured")
running_for=$(docker inspect -f '{{.State.StartedAt}}' "$container_name" | xargs date +"%d days %H hours %M minutes" -d "now - $(date -d "$(docker inspect -f '{{.State.StartedAt}}' "$container_name")" +%s) seconds ago")

echo "Status: $status"
echo "Health: $health_status"
echo "Running for: $running_for"

# Check processes in container
echo -e "\nProcesses in container:"
docker exec "$container_name" ps -ef || echo "Could not get process list"

# Check for recent logs
echo -e "\nRecent logs:"
docker logs --tail 5 "$container_name"

echo -e "\nContainer details:"
docker inspect -f '{{json .State}}' "$container_name" | jq .

echo -e "\nDone."
