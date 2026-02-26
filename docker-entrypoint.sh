#!/bin/sh
set -e

# Log function with timestamp
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a /logs/entrypoint.log
}

# Error handler
error_exit() {
  log "ERROR: $1"
  exit 1
}

log "=== PIA WireGuard Generator Starting ==="
log "Container: $(hostname)"
log "Alpine version: $(cat /etc/alpine-release)"

# Verify required binaries
for cmd in curl jq wg crond; do
  command -v "$cmd" >/dev/null 2>&1 || error_exit "$cmd not found in PATH"
done
log "All required binaries found"

# Check if we're running in Vault mode
if [ -n "$VAULT_ADDR" ] && [ -n "$VAULT_TOKEN" ]; then
    log "Vault mode detected"
    log "Vault address: $VAULT_ADDR"
    
    if [ -f /vault-shared/scripts/vault-init-container.sh ]; then
        log "Sourcing Vault init script..."
        if ! . /vault-shared/scripts/vault-init-container.sh; then
            error_exit "Failed to source Vault init script"
        fi
        
        log "Fetching secrets from Vault..."
        if ! fetch_and_export 'secret/data/pia/general' 'PIA_PASS' 'pia_pass'; then
            error_exit "Failed to fetch PIA_PASS from Vault"
        fi
        log "Vault secrets fetched successfully"
    else
        log "WARNING: Vault variables set but init script not found at /vault-shared/scripts/vault-init-container.sh"
        log "Falling back to environment variables"
    fi
else
    log "Using environment variables for credentials"
fi

# Validate required parameters
if [ -z "$PIA_USER" ] || [ "$PIA_USER" = "your_pia_username" ]; then
    error_exit "PIA_USER must be provided and cannot be 'your_pia_username'"
fi

if [ -z "$PIA_PASS" ] || [ "$PIA_PASS" = "your_pia_password" ]; then
    error_exit "PIA_PASS must be provided via Vault or environment"
fi

log "Configuration validated"
log "PIA User: ${PIA_USER:0:4}****"
log "Regions: $REGIONS"
log "Update interval: $UPDATE_INTERVAL"
log "Config directory: $CONFIG_DIR"
log "Debug mode: $DEBUG"

# Create credentials file with restricted permissions
log "Setting up credentials file..."
mkdir -p /app/ca
cat > /app/credentials.properties <<CREDS
PIA_USER=$PIA_USER
PIA_PASS=$PIA_PASS
CREDS
chmod 600 /app/credentials.properties
log "Credentials file created with mode 600"

# Create regions file
log "Setting up regions file..."
echo "$REGIONS" | tr ',' '\n' > /app/regions.properties
log "Regions configured: $(wc -l < /app/regions.properties) region(s)"

# Make sure output directory exists
mkdir -p "$CONFIG_DIR" /logs
log "Output directories created"

# Run initial configuration
log "Running initial WireGuard configuration generation..."
log "Cleaning up old configuration files..."
rm -f /app/configs/*.conf "$CONFIG_DIR"/*.conf

# Generate new config files (credentials still in environment for initial run)
log "Executing pia-wg-cfg-generator.sh..."
if cd /app && ./pia-wg-cfg-generator.sh; then
    log "Generator script completed successfully"
else
    error_exit "Generator script failed with exit code $?"
fi

# NOW safe to unset after initial run
unset PIA_USER PIA_PASS
log "Credentials cleared from environment"

# Copy configs to output directory
log "Copying configs to $CONFIG_DIR..."
config_count=0
if ls /app/configs/*.conf 1> /dev/null 2>&1; then
    cp -v /app/configs/*.conf "$CONFIG_DIR/" 2>&1 | tee -a /logs/entrypoint.log
    config_count=$(ls -1 "$CONFIG_DIR"/*.conf 2>/dev/null | wc -l)
    log "Successfully copied $config_count configuration file(s)"
else
    log "WARNING: No configs generated initially - this may be expected on first run"
fi

# Create a wrapper script for cron
log "Creating cron wrapper script..."
cat > /app/cron-wrapper.sh <<'WRAPPER'
#!/bin/sh
set -e

LOG_FILE="/logs/cron-output.log"
MAX_LOG_SIZE=10485760  # 10MB

# Rotate log if too large
if [ -f "$LOG_FILE" ] && [ "$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE")" -gt "$MAX_LOG_SIZE" ]; then
    mv "$LOG_FILE" "$LOG_FILE.old"
    echo "Log rotated at $(date)" > "$LOG_FILE"
fi

# Source credentials from file
if [ -f /app/credentials.properties ]; then
    . /app/credentials.properties
    export PIA_USER PIA_PASS
else
    echo "ERROR: Credentials file not found!" >> "$LOG_FILE"
    exit 1
fi

# Source regions from file
if [ -f /app/regions.properties ]; then
    REGIONS=$(tr '\n' ',' < /app/regions.properties | sed 's/,$//')
    export REGIONS
else
    echo "ERROR: Regions file not found!" >> "$LOG_FILE"
    exit 1
fi

CONFIG_DIR=${CONFIG_DIR:-/configs}
DEBUG=${DEBUG:-0}
export CONFIG_DIR DEBUG

# Run the generator
{
    echo ""
    echo "=========================================="
    echo "WireGuard Config Generator Run"
    echo "Started: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "=========================================="
    
    cd /app || exit 1
    
    # Clean old configs
    echo "Cleaning old configurations..."
    rm -f /app/configs/*.conf "$CONFIG_DIR"/*.conf
    
    # Generate new configs
    echo "Generating new configurations..."
    if ./pia-wg-cfg-generator.sh; then
        echo "Generator completed successfully"
        
        # Check if configs were created
        if ls /app/configs/*.conf 1> /dev/null 2>&1; then
            config_count=$(ls -1 /app/configs/*.conf | wc -l)
            echo "Generated $config_count configuration(s)"
            
            # Copy to output directory
            echo "Copying configurations to $CONFIG_DIR..."
            cp -v /app/configs/*.conf "$CONFIG_DIR/"
            
            echo "SUCCESS: Configs updated successfully"
        else
            echo "ERROR: No configs generated!"
            exit 1
        fi
    else
        exit_code=$?
        echo "ERROR: Generator script failed with exit code $exit_code"
        exit "$exit_code"
    fi
    
    echo "Completed: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "=========================================="
    echo ""
    
} >> "$LOG_FILE" 2>&1

# Clean up sensitive variables
unset PIA_USER PIA_PASS

exit 0
WRAPPER

chmod +x /app/cron-wrapper.sh
log "Cron wrapper script created"

# Setup cron
log "Setting up cron job with schedule: $UPDATE_INTERVAL"
cat > /tmp/pia-cron <<CRON
# PIA WireGuard Config Generator
# Logs: /logs/cron-output.log
MAILTO=""
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

$UPDATE_INTERVAL /app/cron-wrapper.sh
CRON

crontab /tmp/pia-cron
rm /tmp/pia-cron
log "Crontab installed"

# Verify crontab
log "Active crontab:"
crontab -l | while IFS= read -r line; do
    log "  $line"
done

# Create startup marker
touch /app/startup_complete
log "Startup marker created"

log "=== Initialization Complete ==="
log "Initial config count: $config_count"
log "Next scheduled run: $(date -d "$(echo "$UPDATE_INTERVAL" | awk '{print $1, $2, $3, $4, $5}')" 2>/dev/null || echo 'See crontab schedule')"
log "Monitor logs: tail -f /logs/cron-output.log"
log "Starting cron daemon..."

# Start cron in foreground
exec crond -f -l 2