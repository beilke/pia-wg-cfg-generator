#!/bin/bash

# Configuration
DOCKERHUB_USERNAME="fbeilke"  # Your DockerHub username
IMAGE_NAME="pia-wg-generator"
VERSION="1.0.1"  # Updated version

# Check if logged in to DockerHub
echo "Checking DockerHub login status..."
if ! docker info | grep -q "Username"; then
  echo "Not logged in to DockerHub. Please run 'docker login' first."
  exit 1
fi

# Create a simplified version of our Dockerfile specifically for DockerHub
cat > Dockerfile.fixed <<EOF
FROM alpine:3.18.3

# Install required dependencies
RUN apk add --no-cache bash curl jq wireguard-tools iputils bc ca-certificates

# Create app directory
WORKDIR /app

# Create directories
RUN mkdir -p /app/ca /app/configs /app/logs

# Set environment variables with defaults
ENV PIA_USER="your_pia_username" \\
    PIA_PASS="your_pia_password" \\
    REGIONS="uk" \\
    UPDATE_INTERVAL="0 */12 * * *" \\
    CONFIG_DIR="/configs" \\
    DEBUG="0"

# Copy the startup script directly to the image
COPY container_start.fixed.sh /app/container_start.sh
RUN chmod +x /app/container_start.sh

# Copy all other script files
COPY *.sh /app/
RUN chmod +x /app/*.sh

# Define volume for configs
VOLUME ["/configs"]

# Simple entrypoint script - using ENTRYPOINT instead of CMD for better reliability
ENTRYPOINT ["/bin/sh", "/app/container_start.sh"]
EOF

# Create an improved version of the container_start script
cat > container_start.fixed.sh <<'EOF'
#!/bin/sh

# Log function
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log "Starting PIA WireGuard Config Generator"
log "PID of main process: $$"

# Handle termination signals
trap 'log "Received termination signal. Shutting down..."; exit 0' SIGTERM SIGINT

# Create credentials file
log "Setting up credentials"
mkdir -p /app/ca
cat > /app/credentials.properties <<CREDS
PIA_USER=$PIA_USER
PIA_PASS=$PIA_PASS
CREDS
chmod 600 /app/credentials.properties

# Create regions file
log "Setting up regions"
echo "$REGIONS" | tr ',' '\n' > /app/regions.properties

# Make sure output directory exists
mkdir -p "$CONFIG_DIR"

# Run initial generation
log "Running initial configuration"
/app/pia-wg-cfg-generator.sh

# Copy configs to output directory
log "Copying configs to $CONFIG_DIR"
cp -v /app/configs/*.conf "$CONFIG_DIR/" || log "No configs generated"

# Set up recurring updates using a simple background loop
log "Starting update loop with interval: $UPDATE_INTERVAL"
(
  while true; do
    # Sleep based on interval
    sleep_time=43200  # Default 12 hours in seconds
    case "$UPDATE_INTERVAL" in
      "0 */1 * * *") sleep_time=3600 ;;      # 1 hour
      "0 */2 * * *") sleep_time=7200 ;;      # 2 hours
      "0 */4 * * *") sleep_time=14400 ;;     # 4 hours
      "0 */6 * * *") sleep_time=21600 ;;     # 6 hours
      "0 */12 * * *") sleep_time=43200 ;;    # 12 hours
      "0 0 * * *") sleep_time=86400 ;;       # 24 hours
      *) log "Using default 12 hour interval" ;;
    esac
    
    log "Next update in $(($sleep_time / 60)) minutes"
    sleep "$sleep_time"
    
    log "Running scheduled update"
    /app/pia-wg-cfg-generator.sh
    cp -v /app/configs/*.conf "$CONFIG_DIR/" || log "No configs generated"
  done
) &

# Create a status file for healthchecks
echo "Container running" > /app/status

# Keep main process running and handle signals properly
log "Setup complete, container running with PID $$"

# Using while loop instead of tail -f for better signal handling
while true; do
  sleep 3600 & wait $!
done
EOF

chmod +x container_start.fixed.sh

# Build the image
echo "Building Docker image..."
docker build -f Dockerfile.fixed -t $IMAGE_NAME:fixed .

# Tag the image with version and latest
echo "Tagging images..."
docker tag $IMAGE_NAME:fixed $DOCKERHUB_USERNAME/$IMAGE_NAME:$VERSION
docker tag $IMAGE_NAME:fixed $DOCKERHUB_USERNAME/$IMAGE_NAME:latest

# Push to DockerHub
echo "Pushing to DockerHub..."
docker push $DOCKERHUB_USERNAME/$IMAGE_NAME:$VERSION
docker push $DOCKERHUB_USERNAME/$IMAGE_NAME:latest

echo "Successfully pushed $DOCKERHUB_USERNAME/$IMAGE_NAME:$VERSION to DockerHub"
echo "Also pushed as $DOCKERHUB_USERNAME/$IMAGE_NAME:latest"
echo ""
echo "Please try with the updated docker-compose.fixed.yml file:"
echo "docker-compose -f docker-compose.fixed.yml up -d"
