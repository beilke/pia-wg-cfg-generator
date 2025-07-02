#!/bin/bash

# Configuration
DOCKERHUB_USERNAME="fbeilke"  # Your DockerHub username
IMAGE_NAME="pia-wg-generator"
VERSION="1.0.2"  # Updated version

# Check if logged in to DockerHub
echo "Checking DockerHub login status..."
if ! docker info | grep -q "Username"; then
  echo "Not logged in to DockerHub. Please run 'docker login' first."
  exit 1
fi

# Create an ultra-simplified Dockerfile that just runs the script directly
cat > Dockerfile.ultra <<EOF
FROM alpine:3.18.3

# Install required dependencies
RUN apk add --no-cache bash curl jq wireguard-tools iputils bc ca-certificates

# Create app directory and needed directories
WORKDIR /app
RUN mkdir -p /app/ca /app/configs /app/logs

# Copy all scripts
COPY *.sh /app/
RUN chmod +x /app/*.sh

# Create the startup script
RUN echo '#!/bin/sh' > /app/entrypoint.sh && \
    echo 'mkdir -p /app/ca' >> /app/entrypoint.sh && \
    echo 'echo "PIA_USER=\$PIA_USER" > /app/credentials.properties' >> /app/entrypoint.sh && \
    echo 'echo "PIA_PASS=\$PIA_PASS" >> /app/credentials.properties' >> /app/entrypoint.sh && \
    echo 'chmod 600 /app/credentials.properties' >> /app/entrypoint.sh && \
    echo 'echo "\$REGIONS" | tr "," "\n" > /app/regions.properties' >> /app/entrypoint.sh && \
    echo 'mkdir -p "\$CONFIG_DIR"' >> /app/entrypoint.sh && \
    echo 'echo "Starting PIA WireGuard Config Generator"' >> /app/entrypoint.sh && \
    echo '/app/pia-wg-cfg-generator.sh' >> /app/entrypoint.sh && \
    echo 'cp -v /app/configs/*.conf "\$CONFIG_DIR/" || echo "No configs generated"' >> /app/entrypoint.sh && \
    echo 'echo "Configuration complete. Sleeping..."' >> /app/entrypoint.sh && \
    echo 'while true; do sleep 3600; done' >> /app/entrypoint.sh && \
    chmod +x /app/entrypoint.sh

# Set environment variables with defaults
ENV PIA_USER="your_pia_username" \
    PIA_PASS="your_pia_password" \
    REGIONS="uk" \
    UPDATE_INTERVAL="0 */12 * * *" \
    CONFIG_DIR="/configs" \
    DEBUG="0"

# Define volume for configs
VOLUME ["/configs"]

# Use simple entrypoint
CMD ["/bin/sh", "/app/entrypoint.sh"]
EOF

# Build the image
echo "Building ultra-simplified Docker image..."
docker build -f Dockerfile.ultra -t $IMAGE_NAME:ultra .

# Tag the image with version and latest
echo "Tagging images..."
docker tag $IMAGE_NAME:ultra $DOCKERHUB_USERNAME/$IMAGE_NAME:$VERSION
docker tag $IMAGE_NAME:ultra $DOCKERHUB_USERNAME/$IMAGE_NAME:latest

# Push to DockerHub
echo "Pushing to DockerHub..."
docker push $DOCKERHUB_USERNAME/$IMAGE_NAME:$VERSION
docker push $DOCKERHUB_USERNAME/$IMAGE_NAME:latest

echo "Successfully pushed ultra-simplified $DOCKERHUB_USERNAME/$IMAGE_NAME:$VERSION to DockerHub"
echo "Also pushed as $DOCKERHUB_USERNAME/$IMAGE_NAME:latest"
