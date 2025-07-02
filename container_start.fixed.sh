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
