#!/bin/bash
set -e

# Log with timestamp
log() {
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "$timestamp - $1" >> /app/logs/app.log
    echo "$timestamp - $1"
}

log "Starting WireGuard configuration update..."

# Create directories if they don't exist
mkdir -p /app/configs
mkdir -p ${CONFIG_DIR}

# Remove all .conf files from configs/ directory
log "Cleaning up old configuration files..."
rm -f /app/configs/*.conf

# Remove all .conf files from output directory
log "Cleaning up old output files in ${CONFIG_DIR}..."
rm -f ${CONFIG_DIR}/*.conf

# Run the WireGuard config generator
log "Running WireGuard config generator..."
if ! /app/pia-wg-cfg-generator.sh 2>&1 | tee -a /app/logs/generator.log; then
    log "ERROR: WireGuard config generator failed!"
    exit 1
fi

# Check if any configs were generated
if [ ! "$(ls -A /app/configs/*.conf 2>/dev/null)" ]; then
    log "ERROR: No configuration files were generated!"
    exit 1
fi

# Copy generated .conf files to output directory
log "Copying configuration files to output directory..."
cp -v /app/configs/*.conf ${CONFIG_DIR}/ 2>&1 | tee -a /app/logs/copy.log

# Count the number of configs generated
CONFIG_COUNT=$(ls -1 ${CONFIG_DIR}/*.conf 2>/dev/null | wc -l)
log "Successfully generated ${CONFIG_COUNT} configuration files."

log "WireGuard configuration update completed successfully."
