#!/bin/bash
set -e

# Ensure logs directory exists
mkdir -p /app/logs

# Function to log messages
log() {
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "$timestamp - $1" >> /app/logs/app.log
    echo "$timestamp - $1"
}

# Validate required parameters
if [ "$PIA_USER" = "your_pia_username" ] || [ "$PIA_PASS" = "your_pia_password" ]; then
    log "ERROR: PIA_USER and PIA_PASS must be provided. Run with -e PIA_USER=username -e PIA_PASS=password"
    exit 1
fi

log "Starting PIA WireGuard Config Generator..."
log "Using regions: $REGIONS"
log "Update interval: $UPDATE_INTERVAL"
log "Config directory: $CONFIG_DIR"

# Create credentials.properties file
log "Setting up credentials..."
cat > /app/credentials.properties <<EOF
PIA_USER=$PIA_USER
PIA_PASS=$PIA_PASS
EOF
chmod 600 /app/credentials.properties

# Create regions.properties file
log "Setting up regions..."
echo "$REGIONS" | tr ',' '\n' > /app/regions.properties
chmod 644 /app/regions.properties

# Create directory for config output if it doesn't exist
mkdir -p "$CONFIG_DIR"
chmod 755 "$CONFIG_DIR"

# Make sure the update script is executable
chmod +x /app/docker_update_wireguard_configs.sh

# Set up cron job
log "Setting up cron job with schedule: $UPDATE_INTERVAL"
echo "$UPDATE_INTERVAL /app/docker_update_wireguard_configs.sh >> /proc/1/fd/1 2>&1" > /etc/crontabs/root
chmod 0644 /etc/crontabs/root

# Run update script once at startup
log "Running initial configuration..."
/app/docker_update_wireguard_configs.sh

# Start cron service
log "Starting cron service..."
crond

# Create a marker file to indicate successful startup
touch /app/startup_complete

log "Container setup complete, running in daemon mode"

# With tini as our init system, we can now just wait indefinitely
# tini will properly handle signals and zombie processes
while true; do
  sleep 3600 & wait $!
done
