#!/bin/bash

# Stop and remove the container if it's running
docker kill $(docker ps -aqf "name=pia-wg-generator") 2>/dev/null || true
docker rm $(docker ps -aqf "name=pia-wg-generator") 2>/dev/null || true

# Create a simplified version of our Dockerfile that should work more reliably with Alpine
cat > Dockerfile.alpine <<EOF
FROM alpine:3.18.3

# Install required dependencies
RUN apk add --no-cache bash curl jq wireguard-tools iputils bc ca-certificates

# Create app directory
WORKDIR /app

# Copy application files
COPY *.sh /app/
RUN chmod +x /app/*.sh

# Create directories
RUN mkdir -p /app/ca /app/configs /app/logs

# Set environment variables with defaults
ENV PIA_USER="your_pia_username" \\
    PIA_PASS="your_pia_password" \\
    REGIONS="uk" \\
    UPDATE_INTERVAL="0 */12 * * *" \\
    CONFIG_DIR="/configs" \\
    DEBUG="0"

# Define volume for configs
VOLUME ["/configs"]

# Simple entrypoint script
CMD ["/app/container_start.sh"]
EOF

# Create a simple start script that does everything in one process
cat > container_start.sh <<EOF
#!/bin/sh
set -e

# Log function
log() {
  echo "\$(date '+%Y-%m-%d %H:%M:%S') - \$1"
}

log "Starting PIA WireGuard Config Generator"

# Create credentials file
log "Setting up credentials"
mkdir -p /app/ca
cat > /app/credentials.properties <<CREDS
PIA_USER=\$PIA_USER
PIA_PASS=\$PIA_PASS
CREDS
chmod 600 /app/credentials.properties

# Create regions file
log "Setting up regions"
echo "\$REGIONS" | tr ',' '\n' > /app/regions.properties

# Make sure output directory exists
mkdir -p "\$CONFIG_DIR"

# Run initial generation
log "Running initial configuration"
/app/pia-wg-cfg-generator.sh

# Copy configs to output directory
log "Copying configs to \$CONFIG_DIR"
cp -v /app/configs/*.conf "\$CONFIG_DIR/" || log "No configs generated"

# Set up recurring updates using a simple background loop
log "Starting update loop with interval: \$UPDATE_INTERVAL"
(
  while true; do
    # Sleep based on interval
    sleep_time=43200  # Default 12 hours in seconds
    case "\$UPDATE_INTERVAL" in
      "0 */1 * * *") sleep_time=3600 ;;      # 1 hour
      "0 */2 * * *") sleep_time=7200 ;;      # 2 hours
      "0 */4 * * *") sleep_time=14400 ;;     # 4 hours
      "0 */6 * * *") sleep_time=21600 ;;     # 6 hours
      "0 */12 * * *") sleep_time=43200 ;;    # 12 hours
      "0 0 * * *") sleep_time=86400 ;;       # 24 hours
      *) log "Using default 12 hour interval" ;;
    esac
    
    log "Next update in \$((\$sleep_time / 60)) minutes"
    sleep "\$sleep_time"
    
    log "Running scheduled update"
    /app/pia-wg-cfg-generator.sh
    cp -v /app/configs/*.conf "\$CONFIG_DIR/" || log "No configs generated"
  done
) &

# Keep main process running and handle signals properly
log "Setup complete, container running"
tail -f /dev/null
EOF

chmod +x container_start.sh

# Build the image
docker build -f Dockerfile.alpine -t pia-wg-generator .

# Run the container
docker run -d \
      -e PIA_USER=p2259420 \
      -e PIA_PASS=P9gjrgN3BY \
      -e REGIONS=br,de_berlin,denmark,france,de-frankfurt,nl_amsterdam,no,sweden,swiss,uk \
      -e UPDATE_INTERVAL="0 */12 * * *" \
      -e CONFIG_DIR=/configs \
      -e DEBUG=0 \
      -v /volume1/docker/pia-wireguard/generated_configs:/configs \
      --name pia-wg-generator \
      --restart unless-stopped \
      pia-wg-generator:latest

# Print helpful message
echo "Container started. View logs with: docker logs pia-wg-generator"
