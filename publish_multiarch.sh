#!/bin/bash

# Configuration
DOCKERHUB_USERNAME="your_dockerhub_username"  # Replace with your DockerHub username
IMAGE_NAME="pia-wg-generator"
VERSION="1.0.0"  # Update this version when making changes

# Check if logged in to DockerHub
echo "Checking DockerHub login status..."
if ! docker info | grep -q "Username: $DOCKERHUB_USERNAME"; then
  echo "Not logged in to DockerHub. Please run 'docker login' first."
  exit 1
fi

# Check if Docker Buildx is installed
if ! docker buildx version >/dev/null 2>&1; then
  echo "Docker Buildx is not installed. Please install it first."
  echo "See: https://docs.docker.com/buildx/working-with-buildx/"
  exit 1
fi

# Create or use buildx builder
if ! docker buildx inspect multiarch >/dev/null 2>&1; then
  echo "Creating new buildx builder 'multiarch'..."
  docker buildx create --name multiarch --use
else
  echo "Using existing buildx builder 'multiarch'..."
  docker buildx use multiarch
fi

# Create a simplified version of our Dockerfile specifically for DockerHub
cat > Dockerfile.multiarch <<EOF
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

# Create the container_start.sh script
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

# Build and push multi-architecture image
echo "Building and pushing multi-architecture image..."
docker buildx build --platform linux/amd64,linux/arm64,linux/arm/v7 \
  -f Dockerfile.multiarch \
  -t $DOCKERHUB_USERNAME/$IMAGE_NAME:$VERSION \
  -t $DOCKERHUB_USERNAME/$IMAGE_NAME:latest \
  --push .

echo "Successfully pushed multi-architecture $DOCKERHUB_USERNAME/$IMAGE_NAME:$VERSION to DockerHub"
echo "Also pushed as $DOCKERHUB_USERNAME/$IMAGE_NAME:latest"
echo ""
echo "Users can pull your image with:"
echo "docker pull $DOCKERHUB_USERNAME/$IMAGE_NAME:latest"
