FROM alpine:3.18.3

# Install dependencies (added openssl)
RUN apk add --no-cache \
    bash \
    curl \
    jq \
    wireguard-tools \
    iputils \
    bc \
    dcron \
    tini \
    ca-certificates \
    openssl && \
    mkdir -p /app/ca /app/configs /app/logs

WORKDIR /app

# Copy all shell scripts
COPY *.sh ./

# Fix line endings, make executable, and verify entrypoint exists
RUN set -ex && \
    echo "=== Processing Shell Scripts ===" && \
    ls -la *.sh && \
    echo "" && \
    echo "Fixing line endings (CRLF -> LF)..." && \
    sed -i 's/\r$//' *.sh && \
    echo "✓ Line endings fixed" && \
    echo "" && \
    echo "Making scripts executable..." && \
    chmod +x *.sh && \
    ls -la *.sh && \
    echo "✓ Scripts are executable" && \
    echo "" && \
    echo "Verifying docker-entrypoint.sh..." && \
    test -f /app/docker-entrypoint.sh || (echo "✗ ERROR: docker-entrypoint.sh not found!" && exit 1) && \
    echo "✓ docker-entrypoint.sh exists" && \
    echo "" && \
    echo "Checking shebang line..." && \
    head -1 /app/docker-entrypoint.sh && \
    echo "" && \
    echo "Checking for carriage returns..." && \
    if grep -q $'\r' /app/docker-entrypoint.sh; then \
        echo "✗ WARNING: Carriage returns still present!"; \
    else \
        echo "✓ No carriage returns found"; \
    fi && \
    echo "" && \
    echo "=== All Scripts Processed Successfully ==="

# Set environment variables
ENV PIA_USER="your_pia_username" \
    PIA_PASS="your_pia_password" \
    REGIONS="uk" \
    UPDATE_INTERVAL="0 */12 * * *" \
    CONFIG_DIR="/configs" \
    DEBUG="0"

# Healthcheck
HEALTHCHECK --interval=5m --timeout=30s --start-period=2m --retries=3 \
  CMD test -f /app/startup_complete && pgrep crond > /dev/null || exit 1

VOLUME ["/configs", "/logs"]

ENTRYPOINT ["/sbin/tini", "--", "/app/docker-entrypoint.sh"]