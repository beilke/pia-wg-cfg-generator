FROM alpine:3.18.3 AS base

# Install required dependencies for the final image
RUN apk add --no-cache \
    bash \
    curl \
    jq \
    wireguard-tools \
    iputils \
    bc \
    dcron \
    tini \
    ca-certificates

FROM base

# Create app directory
WORKDIR /app

# Copy application files
COPY *.sh /app/

# Create ca directory (certificate will be downloaded if not present)
RUN mkdir -p /app/ca

# Create directories
RUN mkdir -p /app/configs /app/logs \
    && chmod +x /app/*.sh

# Create entrypoint script
COPY docker-entrypoint.sh /app/
RUN chmod +x /app/docker-entrypoint.sh

# Set environment variables with defaults
ENV PIA_USER="your_pia_username" \
    PIA_PASS="your_pia_password" \
    REGIONS="uk" \
    UPDATE_INTERVAL="0 */12 * * *" \
    CONFIG_DIR="/configs" \
    DEBUG="0"

# Add healthcheck
HEALTHCHECK --interval=5m --timeout=30s --start-period=1m --retries=3 \
  CMD test -f /app/startup_complete && pgrep crond || exit 1

# Define volume for configs
VOLUME ["/configs"]

# Use tini as init
ENTRYPOINT ["/sbin/tini", "--", "/app/docker-entrypoint.sh"]
