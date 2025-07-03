#!/bin/bash
# Script to build and publish the PIA WireGuard Config Generator image to DockerHub

# Configuration
DOCKERHUB_USERNAME="fbeilke"  # Your DockerHub username
IMAGE_NAME="pia-wg-generator"
VERSION="1.1.0"  # Updated version with cron fix

# Check Docker status
echo "Checking Docker status..."
if ! docker info > /dev/null 2>&1; then
  echo "Error: Docker is not running or not accessible"
  exit 1
fi

# Check login status and attempt login if necessary
echo "Checking DockerHub login status..."
if ! docker info | grep -q "Username"; then
  echo "Not logged in to DockerHub. Attempting login..."
  
  # Prompt for username and password
  read -p "DockerHub Username: " DOCKER_USERNAME
  read -s -p "DockerHub Password: " DOCKER_PASSWORD
  echo
  
  # Try to login
  if ! echo "$DOCKER_PASSWORD" | docker login --username "$DOCKER_USERNAME" --password-stdin; then
    echo "Login failed. Please check your credentials and try again."
    exit 1
  fi
  echo "Login successful!"
else
  echo "Already logged in to DockerHub."
fi

# Stop and remove any existing container
echo "Cleaning up existing containers..."
docker kill $(docker ps -aqf "name=$IMAGE_NAME") 2>/dev/null || true
docker rm $(docker ps -aqf "name=$IMAGE_NAME") 2>/dev/null || true

# Create a Dockerfile with our fixes
cat > Dockerfile.dockerhub <<EOF
FROM alpine:3.18.3

# Install required dependencies
RUN apk add --no-cache bash curl jq wireguard-tools iputils bc dcron tini ca-certificates

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

# Add healthcheck
HEALTHCHECK --interval=5m --timeout=30s --start-period=1m --retries=3 \\
  CMD test -f /app/startup_complete && pgrep crond || exit 1

# Define volume for configs
VOLUME ["/configs"]

# Use tini as init
ENTRYPOINT ["/sbin/tini", "--", "/app/docker-entrypoint.sh"]
EOF

# Create our fixed entrypoint script with simple cron setup
cat > docker-entrypoint.sh <<EOF
#!/bin/sh
set -e

# Log function
log() {
  echo "\$(date '+%Y-%m-%d %H:%M:%S') - \$1"
}

# Validate required parameters
if [ "\$PIA_USER" = "your_pia_username" ] || [ "\$PIA_PASS" = "your_pia_password" ]; then
    log "ERROR: PIA_USER and PIA_PASS must be provided. Run with -e PIA_USER=username -e PIA_PASS=password"
    exit 1
fi

log "Starting PIA WireGuard Config Generator..."
log "Using regions: \$REGIONS"
log "Update interval: \$UPDATE_INTERVAL"
log "Config directory: \$CONFIG_DIR"

# Create credentials file
log "Setting up credentials..."
mkdir -p /app/ca
cat > /app/credentials.properties <<CREDS
PIA_USER=\$PIA_USER
PIA_PASS=\$PIA_PASS
CREDS
chmod 600 /app/credentials.properties

# Create regions file
log "Setting up regions..."
echo "\$REGIONS" | tr ',' '\n' > /app/regions.properties

# Make sure output directory exists
mkdir -p "\$CONFIG_DIR"

# Run initial configuration
log "Running initial configuration..."

# First, clean up old config files
log "Cleaning up old configuration files..."
rm -f /app/configs/*.conf
log "Cleaning up old output files in \$CONFIG_DIR..."
rm -f "\$CONFIG_DIR"/*.conf

# Now generate new config files
cd /app && ./pia-wg-cfg-generator.sh

# Copy configs to output directory
log "Copying configs to \$CONFIG_DIR..."
cp -v /app/configs/*.conf "\$CONFIG_DIR/" 2>/dev/null || log "No configs generated initially"

# Create a simple cron job that preserves environment variables
log "Setting up cron job with schedule: \$UPDATE_INTERVAL"

# Create the cron command - very simple to avoid syntax issues
CRON_CMD="cd /app && rm -f /app/configs/*.conf && rm -f \$CONFIG_DIR/*.conf && PIA_USER='\$PIA_USER' PIA_PASS='\$PIA_PASS' REGIONS='\$REGIONS' CONFIG_DIR='\$CONFIG_DIR' DEBUG='\$DEBUG' ./pia-wg-cfg-generator.sh && cp -v /app/configs/*.conf \$CONFIG_DIR/ 2>/dev/null"

# Write the cron job to a temporary file with environment variables preserved
cat > /tmp/pia-cron <<CFILE
\$UPDATE_INTERVAL \$CRON_CMD
CFILE

# Install the cron job
log "Installing crontab..."
crontab /tmp/pia-cron
rm /tmp/pia-cron

# List the installed crontab for verification
log "Installed crontab:"
crontab -l | log

# Create startup marker file for healthcheck
touch /app/startup_complete

# Start cron in the foreground
log "Starting cron service..."
exec crond -f -l 8
EOF

chmod +x docker-entrypoint.sh

# Build the image
echo "Building Docker image..."
docker build -f Dockerfile.dockerhub -t $IMAGE_NAME:latest .

# Tag the image with version and latest
echo "Tagging images..."
docker tag $IMAGE_NAME:latest $DOCKERHUB_USERNAME/$IMAGE_NAME:$VERSION
docker tag $IMAGE_NAME:latest $DOCKERHUB_USERNAME/$IMAGE_NAME:latest

# Push to DockerHub
echo "Pushing to DockerHub..."
docker push $DOCKERHUB_USERNAME/$IMAGE_NAME:$VERSION
docker push $DOCKERHUB_USERNAME/$IMAGE_NAME:latest

echo "Successfully pushed $DOCKERHUB_USERNAME/$IMAGE_NAME:$VERSION to DockerHub"
echo "Also pushed as $DOCKERHUB_USERNAME/$IMAGE_NAME:latest"
echo ""
echo "Users can pull your image with:"
echo "docker pull $DOCKERHUB_USERNAME/$IMAGE_NAME:latest"
