#!/bin/sh
set -e

# Log function
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
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

# Create credentials file
log "Setting up credentials..."
mkdir -p /app/ca
cat > /app/credentials.properties <<CREDS
PIA_USER=$PIA_USER
PIA_PASS=$PIA_PASS
CREDS
chmod 600 /app/credentials.properties

# Create regions file
log "Setting up regions..."
echo "$REGIONS" | tr ',' '\n' > /app/regions.properties

# Make sure output directory exists
mkdir -p "$CONFIG_DIR"

# Run initial configuration
log "Running initial configuration..."

# First, clean up old config files
log "Cleaning up old configuration files..."
rm -f /app/configs/*.conf
log "Cleaning up old output files in $CONFIG_DIR..."
rm -f "$CONFIG_DIR"/*.conf

# Now generate new config files
cd /app && ./pia-wg-cfg-generator.sh

# Copy configs to output directory
log "Copying configs to $CONFIG_DIR..."
cp -v /app/configs/*.conf "$CONFIG_DIR/" 2>/dev/null || log "No configs generated initially"

# Create a simple cron job that preserves environment variables
log "Setting up cron job with schedule: $UPDATE_INTERVAL"

# Create the cron command - very simple to avoid syntax issues
CRON_CMD="cd /app && rm -f /app/configs/*.conf && rm -f $CONFIG_DIR/*.conf && PIA_USER='$PIA_USER' PIA_PASS='$PIA_PASS' REGIONS='$REGIONS' CONFIG_DIR='$CONFIG_DIR' DEBUG='$DEBUG' ./pia-wg-cfg-generator.sh && cp -v /app/configs/*.conf $CONFIG_DIR/ 2>/dev/null"

# Write the cron job to a temporary file with environment variables preserved
cat > /tmp/pia-cron <<CFILE
$UPDATE_INTERVAL $CRON_CMD
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
