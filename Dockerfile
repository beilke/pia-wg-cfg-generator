FROM alpine:3.24.3@sha256:be2656061b536c1883c4034790e21d0a09c5aaaf51968b89368a3c0371ea2c9a

# Refresh inherited packages as well as explicitly installed dependencies.
RUN apk upgrade --no-cache && apk add --no-cache \
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

RUN sed -i 's/\r$//' *.sh && chmod +x *.sh && test -f docker-entrypoint.sh

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