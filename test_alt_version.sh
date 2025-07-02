#!/bin/bash

# Stop and remove the container if it's running
docker kill $(docker ps -aqf "name=pia-wg-generator") 2>/dev/null || true
docker rm $(docker ps -aqf "name=pia-wg-generator") 2>/dev/null || true

# Copy the alternative files for testing
cp Dockerfile.alt Dockerfile.test
cp docker-entrypoint.alt.sh docker-entrypoint.test.sh
chmod +x docker-entrypoint.test.sh

# Build the image using the alternative Dockerfile
docker build -f Dockerfile.test -t pia-wg-generator-test .

# Run the container
docker run -d \
      -e PIA_USER=p2259420 \
      -e PIA_PASS=P9gjrgN3BY \
      -e REGIONS=br,de_berlin,denmark,france,de-frankfurt,nl_amsterdam,no,sweden,swiss,uk \
      -e UPDATE_INTERVAL="0 */12 * * *" \
      -e CONFIG_DIR=/configs \
      -e DEBUG=0 \
      -v /volume1/docker/pia-wireguard/generated_configs:/configs \
      --name pia-wg-generator-test \
      --restart unless-stopped \
      pia-wg-generator-test:latest

# Print helpful message
echo "Test container started. View logs with: docker logs pia-wg-generator-test"
echo "Check status with: docker ps | grep pia-wg-generator-test"
echo ""
echo "Wait about 30 seconds, then run:"
echo "docker inspect -f '{{.State.Status}} {{.State.Health.Status}}' pia-wg-generator-test"
