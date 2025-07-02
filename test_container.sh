#!/bin/bash

# Container name
CONTAINER_NAME="pia-wg-generator"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Stop and remove existing container if it exists
echo "Removing existing container if it exists..."
docker stop $CONTAINER_NAME 2>/dev/null || true
docker rm $CONTAINER_NAME 2>/dev/null || true

# Run the container with minimal settings for testing
echo "Starting container for testing..."
docker run -d \
  --name $CONTAINER_NAME \
  -e PIA_USER=test_user \
  -e PIA_PASS=test_pass \
  -e REGIONS=uk \
  fbeilke/pia-wg-generator:latest

# Wait a bit for the container to start
echo "Waiting 10 seconds for container to initialize..."
sleep 10

# Check container status
CONTAINER_STATUS=$(docker inspect -f '{{.State.Status}}' $CONTAINER_NAME 2>/dev/null)
if [ "$CONTAINER_STATUS" = "running" ]; then
  echo -e "${GREEN}✓ Container is running${NC}"
else
  echo -e "${RED}✗ Container status: $CONTAINER_STATUS${NC}"
fi

# Check container health
CONTAINER_HEALTH=$(docker inspect -f '{{.State.Health.Status}}' $CONTAINER_NAME 2>/dev/null)
if [ -n "$CONTAINER_HEALTH" ]; then
  echo -e "Health status: $CONTAINER_HEALTH"
fi

# Check processes in container
echo -e "\n${YELLOW}Processes in container:${NC}"
docker exec $CONTAINER_NAME ps -ef || echo "Could not list processes"

# Check logs
echo -e "\n${YELLOW}Container logs:${NC}"
docker logs $CONTAINER_NAME | tail -15

# Additional debug info
echo -e "\n${YELLOW}Container entrypoint details:${NC}"
docker inspect -f '{{.Config.Entrypoint}}' $CONTAINER_NAME

echo -e "\n${YELLOW}Container command details:${NC}"
docker inspect -f '{{.Config.Cmd}}' $CONTAINER_NAME

echo -e "\n${YELLOW}Container state:${NC}"
docker inspect -f '{{json .State}}' $CONTAINER_NAME | jq .
