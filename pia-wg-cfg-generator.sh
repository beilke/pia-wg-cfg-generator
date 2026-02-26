#!/bin/bash
set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Configuration
: "${DEBUG:=0}"
: "${MAX_RETRIES:=3}"
: "${RETRY_DELAY:=5}"
: "${PING_COUNT:=3}"
: "${PING_TIMEOUT:=5}"

CA_CERT="./ca/ca.rsa.4096.crt"
PROPERTIES_FILE="./regions.properties"
CREDENTIALS_FILE="./credentials.properties"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*" >&2
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*"
}

debug() {
    if [ "$DEBUG" = "1" ]; then
        echo -e "[DEBUG] $*" >&2
    fi
}

# Cleanup function
cleanup() {
    debug "Cleaning up sensitive data..."
    unset PIA_USER PIA_PASS TOKEN
    rm -f wg_temp.key 2>/dev/null || true
}

trap cleanup EXIT INT TERM

# Retry function for API calls
retry_command() {
    local max_attempts="$1"
    shift
    local attempt=1
    
    while [ $attempt -le "$max_attempts" ]; do
        debug "Attempt $attempt of $max_attempts"
        if "$@"; then
            return 0
        fi
        
        if [ $attempt -lt "$max_attempts" ]; then
            warn "Command failed, retrying in ${RETRY_DELAY}s..."
            sleep "$RETRY_DELAY"
        fi
        ((attempt++))
    done
    
    error "Command failed after $max_attempts attempts"
    return 1
}

# Sanitize filename
sanitize_filename() {
    echo "$1" | tr -cd '[:alnum:]._-' | tr '[:upper:]' '[:lower:]'
}

# Validate region ID
validate_region_id() {
    local region="$1"
    if [[ ! "$region" =~ ^[a-z0-9_-]+$ ]]; then
        error "Invalid region ID: $region"
        return 1
    fi
    return 0
}

# Load credentials securely
load_credentials() {
    if [ ! -f "$CREDENTIALS_FILE" ] || [ ! -s "$CREDENTIALS_FILE" ]; then
        error "Credentials file not found or empty: $CREDENTIALS_FILE"
        return 1
    fi
    
    debug "Reading credentials from: $CREDENTIALS_FILE"
    
    # Check file permissions
    local perms
    perms=$(stat -c '%a' "$CREDENTIALS_FILE" 2>/dev/null || stat -f '%A' "$CREDENTIALS_FILE" 2>/dev/null)
    if [ "$perms" != "600" ] && [ "$perms" != "400" ]; then
        warn "Credentials file has weak permissions: $perms (should be 600)"
    fi
    
    # Read credentials
    PIA_USER=$(grep -E '^PIA_USER=' "$CREDENTIALS_FILE" | cut -d'=' -f2- | tr -d '[:space:]')
    PIA_PASS=$(grep -E '^PIA_PASS=' "$CREDENTIALS_FILE" | cut -d'=' -f2- | tr -d '[:space:]')
    
    if [ -z "$PIA_USER" ] || [ -z "$PIA_PASS" ]; then
        error "Invalid credentials in file"
        return 1
    fi
    
    debug "Credentials loaded successfully"
    return 0
}

# Download CA certificate
download_ca_cert() {
    mkdir -p "$(dirname "$CA_CERT")"
    
    if [ -f "$CA_CERT" ]; then
        debug "CA certificate already exists"
        return 0
    fi
    
    log "Downloading CA certificate..."
    if ! retry_command 3 curl -sf -o "$CA_CERT" \
        "https://raw.githubusercontent.com/pia-foss/manual-connections/master/ca.rsa.4096.crt"; then
        error "Failed to download CA certificate"
        return 1
    fi
    
    log "CA certificate downloaded"
    return 0
}

# Authenticate with PIA
authenticate() {
    log "Authenticating with PIA..."
    
    local response
    if ! response=$(retry_command 3 curl -sf --max-time 30 \
        --request POST \
        "https://www.privateinternetaccess.com/api/client/v2/token" \
        --form "username=$PIA_USER" \
        --form "password=$PIA_PASS"); then
        error "Failed to authenticate with PIA"
        return 1
    fi
    
    debug "Token response received"
    
    TOKEN=$(echo "$response" | jq -r '.token // empty')
    
    if [ -z "$TOKEN" ]; then
        error "Failed to extract token from response"
        debug "Response: $response"
        return 1
    fi
    
    log "Authentication successful"
    return 0
}

# Fetch server list
fetch_server_list() {
    log "Fetching server list..."
    
    local server_list
    if ! server_list=$(retry_command 3 curl -sf --max-time 30 \
        "https://serverlist.piaservers.net/vpninfo/servers/v6"); then
        error "Failed to fetch server list"
        return 1
    fi
    
    # Get first line (actual data)
    SERVER_LIST=$(echo "$server_list" | head -n 1)
    
    if [ -z "$SERVER_LIST" ] || ! echo "$SERVER_LIST" | jq -e . >/dev/null 2>&1; then
        error "Invalid server list received"
        return 1
    fi
    
    log "Server list acquired successfully"
    return 0
}

# Load regions from file
load_regions() {
    if [ ! -f "$PROPERTIES_FILE" ] || [ ! -s "$PROPERTIES_FILE" ]; then
        error "Regions file not found or empty: $PROPERTIES_FILE"
        return 1
    fi
    
    debug "Reading regions from: $PROPERTIES_FILE"
    
    # Read and validate regions
    REGION_IDS=()
    while IFS= read -r region; do
        # Skip empty lines and comments
        [[ -z "$region" || "$region" =~ ^[[:space:]]*# ]] && continue
        
        # Trim whitespace
        region=$(echo "$region" | tr -d '[:space:]')
        
        if validate_region_id "$region"; then
            REGION_IDS+=("$region")
        else
            warn "Skipping invalid region: $region"
        fi
    done < "$PROPERTIES_FILE"
    
    if [ ${#REGION_IDS[@]} -eq 0 ]; then
        error "No valid regions found in properties file"
        return 1
    fi
    
    log "Loaded ${#REGION_IDS[@]} region(s): ${REGION_IDS[*]}"
    return 0
}

# Ping server with timeout and error handling
ping_server() {
    local server="$1"
    local ping_result
    
    # Use timeout command if available, otherwise rely on ping's timeout
    if command -v timeout >/dev/null 2>&1; then
        ping_result=$(timeout "$PING_TIMEOUT" ping -c "$PING_COUNT" -W 2 -q "$server" 2>/dev/null || echo "")
    else
        ping_result=$(ping -c "$PING_COUNT" -W 2 -q "$server" 2>/dev/null || echo "")
    fi
    
    if [ -z "$ping_result" ]; then
        echo "999999"
        return 1
    fi
    
    # Extract average ping time (works with both GNU and BusyBox ping)
    local avg_ping
    avg_ping=$(echo "$ping_result" | awk -F '/' 'END {print ($5 != "" ? $5 : "999999")}')
    
    # Validate it's a number
    if [[ "$avg_ping" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        echo "$avg_ping"
        return 0
    else
        echo "999999"
        return 1
    fi
}

# Find best server for region
find_best_server() {
    local region="$1"
    
    debug "Finding best server for region: $region"
    
    # Get WireGuard servers for this region
    local wg_servers_json
    wg_servers_json=$(echo "$SERVER_LIST" | jq -c --arg reg "$region" \
        '.regions[] | select(.id == $reg) | .servers.wg // empty')
    
    if [ -z "$wg_servers_json" ] || [ "$wg_servers_json" = "null" ]; then
        error "No WireGuard servers found for region: $region"
        return 1
    fi
    
    debug "Found WireGuard servers for $region"
    
    # Parse all servers at once for efficiency
    local servers_data
    servers_data=$(echo "$wg_servers_json" | jq -r '.[] | "\(.ip)|\(.cn)"')
    
    if [ -z "$servers_data" ]; then
        error "Failed to parse server data for region: $region"
        return 1
    fi
    
    local best_server=""
    local best_ping=999999
    local best_host=""
    local server_count=0
    
    while IFS='|' read -r ip hostname; do
        ((server_count++))
        
        log "Testing server $server_count: $ip ($hostname)"
        
        local ping_time
        ping_time=$(ping_server "$ip")
        
        if [ "$ping_time" != "999999" ]; then
            log "  ↳ Ping: ${ping_time}ms"
            
            # Compare using bc for floating point
            if (( $(echo "$ping_time < $best_ping" | bc -l 2>/dev/null || echo 0) )); then
                best_ping="$ping_time"
                best_server="$ip"
                best_host="$hostname"
                debug "New best server: $best_server ($best_ping ms)"
            fi
        else
            warn "  ↳ Server unreachable"
        fi
    done <<< "$servers_data"
    
    if [ -z "$best_server" ]; then
        error "No reachable servers found for region: $region"
        return 1
    fi
    
    log "Best server: $best_server ($best_host) - ${best_ping}ms"
    
    # Export results
    BEST_SERVER="$best_server"
    BEST_HOST="$best_host"
    BEST_PING="$best_ping"
    
    return 0
}

# Generate WireGuard keys securely (no temp files)
generate_wg_keys() {
    debug "Generating WireGuard keys..."
    
    # Generate keys without writing to disk
    PRIVATE_KEY=$(wg genkey)
    PUBLIC_KEY=$(echo "$PRIVATE_KEY" | wg pubkey)
    
    if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
        error "Failed to generate WireGuard keys"
        return 1
    fi
    
    debug "WireGuard keys generated successfully"
    return 0
}

# Register key with PIA (using POST body instead of URL params)
register_key() {
    local host="$1"
    local server="$2"
    local pubkey="$3"
    
    debug "Registering public key with $host ($server)"
    
    local response
    if ! response=$(retry_command 3 curl -sf --max-time 30 \
        --connect-to "$host::$server:" \
        --cacert "$CA_CERT" \
        --request POST \
        --header "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "pt=$TOKEN" \
        --data-urlencode "pubkey=$pubkey" \
        "https://$host:1337/addKey"); then
        error "Failed to register key with server"
        return 1
    fi
    
    debug "Registration response received"
    
    local status
    status=$(echo "$response" | jq -r '.status // empty')
    
    if [ "$status" != "OK" ]; then
        error "Server rejected key registration"
        debug "Response: $response"
        return 1
    fi
    
    # Parse response
    SERVER_KEY=$(echo "$response" | jq -r '.server_key // empty')
    SERVER_PORT=$(echo "$response" | jq -r '.server_port // empty')
    DNS_SERVERS=$(echo "$response" | jq -r '.dns_servers | join(", ") // empty')
    PEER_IP=$(echo "$response" | jq -r '.peer_ip // empty')
    
    if [ -z "$SERVER_KEY" ] || [ -z "$SERVER_PORT" ] || [ -z "$PEER_IP" ]; then
        error "Incomplete response from server"
        debug "Response: $response"
        return 1
    fi
    
    debug "Key registered successfully"
    return 0
}

# Generate WireGuard configuration file
generate_config() {
    local region="$1"
    local hostname="$2"
    local ping="$3"
    local server_ip="$4"
    
    # Sanitize hostname for filename
    local safe_hostname
    safe_hostname=$(sanitize_filename "$hostname")
    
    # Round ping to integer
    local ping_int
    ping_int=$(printf "%.0f" "$ping")
    
    local config_file="./configs/pia-${region}-${safe_hostname}-${ping_int}ms.conf"
    
    debug "Generating config file: $config_file"
    
    mkdir -p "$(dirname "$config_file")"
    
    # Write config atomically (write to temp, then move)
    local temp_file="${config_file}.tmp"
    
    cat > "$temp_file" <<EOF
# PIA WireGuard Configuration
# Region: $region
# Server: $hostname ($server_ip)
# Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')

[Interface]
PrivateKey = $PRIVATE_KEY
Address = $PEER_IP/32
DNS = $DNS_SERVERS

[Peer]
PublicKey = $SERVER_KEY
Endpoint = $server_ip:$SERVER_PORT
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF
    
    # Set restrictive permissions before moving
    chmod 600 "$temp_file"
    
    # Atomic move
    mv "$temp_file" "$config_file"
    
    log "✓ Config generated: $config_file"
    
    return 0
}

# Process a single region
process_region() {
    local region="$1"
    
    log ""
    log "=========================================="
    log "Processing region: $region"
    log "=========================================="
    
    # Find best server
    if ! find_best_server "$region"; then
        error "Failed to find server for region: $region"
        return 1
    fi
    
    # Generate keys
    if ! generate_wg_keys; then
        error "Failed to generate keys for region: $region"
        return 1
    fi
    
    # Register key
    if ! register_key "$BEST_HOST" "$BEST_SERVER" "$PUBLIC_KEY"; then
        error "Failed to register key for region: $region"
        return 1
    fi
    
    # Generate config
    if ! generate_config "$region" "$BEST_HOST" "$BEST_PING" "$BEST_SERVER"; then
        error "Failed to generate config for region: $region"
        return 1
    fi
    
    log "✓ Region $region completed successfully"
    
    # Clean up keys from memory
    unset PRIVATE_KEY PUBLIC_KEY SERVER_KEY
    
    return 0
}

# Main execution
main() {
    log "=== PIA WireGuard Config Generator ==="
    log "Debug mode: $DEBUG"
    
    # Load credentials
    if ! load_credentials; then
        exit 1
    fi
    
    # Download CA cert
    if ! download_ca_cert; then
        exit 1
    fi
    
    # Authenticate
    if ! authenticate; then
        exit 1
    fi
    
    # Clear credentials from memory after auth
    unset PIA_USER PIA_PASS
    
    # Fetch server list
    if ! fetch_server_list; then
        exit 1
    fi
    
    # Load regions
    if ! load_regions; then
        exit 1
    fi
    
    # Process each region
    local success_count=0
    local fail_count=0
    
    for region in "${REGION_IDS[@]}"; do
        if process_region "$region"; then
            ((success_count++))
        else
            ((fail_count++))
            warn "Skipping region $region due to errors"
        fi
    done
    
    log ""
    log "=========================================="
    log "Summary"
    log "=========================================="
    log "Total regions: ${#REGION_IDS[@]}"
    log "Successful: $success_count"
    log "Failed: $fail_count"
    log "=========================================="
    
    if [ $fail_count -gt 0 ]; then
        warn "Some regions failed to process"
        exit 1
    fi
    
    log "✓ All regions processed successfully"
    exit 0
}

# Run main function
main "$@"