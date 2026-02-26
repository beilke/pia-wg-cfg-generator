#!/bin/bash
set -euo pipefail

#=============================================================================
# PIA WireGuard Configuration Generator
# Generates WireGuard configs for Private Internet Access VPN
#=============================================================================

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
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Log file
LOG_FILE="/logs/generator.log"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

#=============================================================================
# Logging Functions
#=============================================================================

log() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] $*"
    echo -e "${GREEN}${msg}${NC}"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

error() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*"
    echo -e "${RED}${msg}${NC}" >&2
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

warn() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $*"
    echo -e "${YELLOW}${msg}${NC}"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

info() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*"
    echo -e "${BLUE}${msg}${NC}"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

debug() {
    if [ "$DEBUG" = "1" ]; then
        local msg="[$(date +'%Y-%m-%d %H:%M:%S')] DEBUG: $*"
        echo -e "${CYAN}${msg}${NC}" >&2
        echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

success() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] ✓ $*"
    echo -e "${GREEN}${msg}${NC}"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

step() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] ▶ $*"
    echo -e "${MAGENTA}${msg}${NC}"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

#=============================================================================
# Cleanup Function
#=============================================================================

cleanup() {
    debug "Cleaning up sensitive data..."
    unset PIA_USER PIA_PASS TOKEN PRIVATE_KEY PUBLIC_KEY
    rm -f wg_temp.key 2>/dev/null || true
}

trap cleanup EXIT INT TERM

#=============================================================================
# Utility Functions
#=============================================================================

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

# URL encode
urlencode() {
    local string="$1"
    printf %s "$string" | jq -sRr @uri
}

#=============================================================================
# Load Credentials
#=============================================================================

load_credentials() {
    step "Loading credentials from $CREDENTIALS_FILE"
    
    if [ ! -f "$CREDENTIALS_FILE" ] || [ ! -s "$CREDENTIALS_FILE" ]; then
        error "Credentials file not found or empty: $CREDENTIALS_FILE"
        return 1
    fi
    
    # Check file permissions
    local perms
    perms=$(stat -c '%a' "$CREDENTIALS_FILE" 2>/dev/null || stat -f '%A' "$CREDENTIALS_FILE" 2>/dev/null || echo "unknown")
    debug "Credentials file permissions: $perms"
    
    if [ "$perms" != "600" ] && [ "$perms" != "400" ] && [ "$perms" != "unknown" ]; then
        warn "Credentials file has weak permissions: $perms (should be 600)"
    fi
    
    # Read credentials
    PIA_USER=$(grep -E '^PIA_USER=' "$CREDENTIALS_FILE" | cut -d'=' -f2- | tr -d '[:space:]')
    PIA_PASS=$(grep -E '^PIA_PASS=' "$CREDENTIALS_FILE" | cut -d'=' -f2- | tr -d '[:space:]')
    
    if [ -z "$PIA_USER" ] || [ -z "$PIA_PASS" ]; then
        error "Invalid credentials in file"
        return 1
    fi
    
    debug "PIA_USER: ${PIA_USER:0:4}****"
    debug "PIA_PASS: ${PIA_PASS:0:2}**** (length: ${#PIA_PASS})"
    success "Credentials loaded"
    return 0
}

#=============================================================================
# Download CA Certificate
#=============================================================================

download_ca_cert() {
    mkdir -p "$(dirname "$CA_CERT")"
    
    if [ -f "$CA_CERT" ]; then
        debug "CA certificate already exists at $CA_CERT"
        
        # Verify it's a valid certificate
        if openssl x509 -in "$CA_CERT" -noout 2>/dev/null; then
            debug "CA certificate is valid"
            return 0
        else
            warn "Existing CA certificate is invalid, re-downloading..."
            rm -f "$CA_CERT"
        fi
    fi
    
    step "Downloading CA certificate..."
    
    local ca_url="https://raw.githubusercontent.com/pia-foss/manual-connections/master/ca.rsa.4096.crt"
    
    if curl -sf --max-time 30 -o "$CA_CERT" "$ca_url"; then
        success "CA certificate downloaded"
        debug "Certificate saved to: $CA_CERT"
        
        # Verify downloaded certificate
        if openssl x509 -in "$CA_CERT" -noout 2>/dev/null; then
            debug "Downloaded certificate is valid"
        else
            error "Downloaded certificate is invalid"
            rm -f "$CA_CERT"
            return 1
        fi
        
        return 0
    else
        error "Failed to download CA certificate from $ca_url"
        return 1
    fi
}

#=============================================================================
# Authenticate with PIA
#=============================================================================

authenticate() {
    step "Authenticating with PIA..."
    debug "API endpoint: https://www.privateinternetaccess.com/api/client/v2/token"
    debug "Username: ${PIA_USER}"
    debug "Password length: ${#PIA_PASS}"
    
    if [ -z "$PIA_USER" ] || [ -z "$PIA_PASS" ]; then
        error "Credentials are empty!"
        return 1
    fi
    
    if ! [[ "$PIA_USER" =~ ^p[0-9]+$ ]]; then
        warn "Username format looks unusual: $PIA_USER (expected: p followed by numbers)"
    fi
    
    local response
    local http_code
    local attempt=1
    local rate_limit_wait=900  # 15 minutes in seconds
    
    while [ $attempt -le "$MAX_RETRIES" ]; do
        info "Authentication attempt $attempt of $MAX_RETRIES"
        
        # Make request with HTTP status code
        local temp_file="/tmp/pia_auth_$$.txt"
        http_code=$(curl -sf -w "%{http_code}" --max-time 30 \
            --request POST \
            --output "$temp_file" \
            "https://www.privateinternetaccess.com/api/client/v2/token" \
            --form "username=$PIA_USER" \
            --form "password=$PIA_PASS" 2>&1)
        
        local curl_exit=$?
        
        if [ -f "$temp_file" ]; then
            response=$(cat "$temp_file")
            rm -f "$temp_file"
        else
            response=""
        fi
        
        debug "Curl exit code: $curl_exit"
        debug "HTTP status code: $http_code"
        debug "Response length: ${#response}"
        
        # Handle successful authentication
        if [ $curl_exit -eq 0 ] && [ "$http_code" = "200" ]; then
            if echo "$response" | jq -e . >/dev/null 2>&1; then
                TOKEN=$(echo "$response" | jq -r '.token // empty')
                
                if [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
                    debug "Token: ${TOKEN:0:10}**** (length: ${#TOKEN})"
                    success "Authentication successful"
                    return 0
                else
                    error "No token in response"
                    debug "Response: $response"
                fi
            else
                error "Invalid JSON response"
                debug "Response: $response"
            fi
        
        # Handle rate limiting (429)
        elif [ "$http_code" = "429" ]; then
            error "Rate limited by PIA API (HTTP 429)"
            
            if echo "$response" | jq -e . >/dev/null 2>&1; then
                local error_msg
                error_msg=$(echo "$response" | jq -r '.message // empty')
                if [ -n "$error_msg" ]; then
                    error "API Message: $error_msg"
                fi
            fi
            
            # Check if we should wait
            if [ $attempt -eq 1 ]; then
                warn "Too many authentication attempts detected"
                warn "PIA rate limit typically resets after 15-30 minutes"
                warn "Waiting ${rate_limit_wait} seconds (15 minutes) before retry..."
                
                # Show countdown
                local remaining=$rate_limit_wait
                while [ $remaining -gt 0 ]; do
                    if [ $((remaining % 60)) -eq 0 ]; then
                        info "Time remaining: $((remaining / 60)) minutes"
                    fi
                    sleep 60
                    remaining=$((remaining - 60))
                done
                
                info "Retrying after rate limit wait..."
                ((attempt++))
                continue
            else
                error "Still rate limited after waiting"
                return 1
            fi
        
        # Handle other errors
        else
            warn "Authentication failed"
            
            if [ -n "$http_code" ] && [ "$http_code" != "000" ]; then
                error "HTTP Status: $http_code"
                
                case "$http_code" in
                    400) error "Bad Request - Check credentials format" ;;
                    401) error "Unauthorized - Invalid username or password" ;;
                    403) error "Forbidden - Account may be suspended" ;;
                    500|502|503) error "PIA Server Error - Try again later" ;;
                esac
                
                # Try to parse error from response
                if [ -n "$response" ] && echo "$response" | jq -e . >/dev/null 2>&1; then
                    local error_msg
                    error_msg=$(echo "$response" | jq -r '.message // .error // empty')
                    if [ -n "$error_msg" ]; then
                        error "API Message: $error_msg"
                    fi
                    debug "Full response: $response"
                fi
            else
                error "Curl error: $curl_exit"
            fi
        fi
        
        if [ $attempt -lt "$MAX_RETRIES" ]; then
            warn "Retrying in ${RETRY_DELAY}s..."
            sleep "$RETRY_DELAY"
        fi
        ((attempt++))
    done
    
    error "Authentication failed after $MAX_RETRIES attempts"
    return 1
}

#=============================================================================
# Fetch Server List
#=============================================================================

fetch_server_list() {
    step "Fetching PIA server list..."
    
    local url="https://serverlist.piaservers.net/vpninfo/servers/v6"
    debug "Server list URL: $url"
    
    local response
    local attempt=1
    
    while [ $attempt -le "$MAX_RETRIES" ]; do
        debug "Fetch attempt $attempt of $MAX_RETRIES"
        
        response=$(curl -sf --max-time 30 "$url" 2>&1)
        local curl_exit=$?
        
        if [ $curl_exit -eq 0 ] && [ -n "$response" ]; then
            # Get first line (actual data)
            SERVER_LIST=$(echo "$response" | head -n 1)
            
            # Validate JSON
            if echo "$SERVER_LIST" | jq -e . >/dev/null 2>&1; then
                local region_count
                region_count=$(echo "$SERVER_LIST" | jq '.regions | length')
                debug "Server list contains $region_count regions"
                success "Server list acquired successfully"
                return 0
            else
                error "Invalid JSON in server list"
                debug "Response: ${SERVER_LIST:0:200}..."
            fi
        else
            warn "Failed to fetch server list (curl exit: $curl_exit)"
            debug "Response: $response"
        fi
        
        if [ $attempt -lt "$MAX_RETRIES" ]; then
            warn "Retrying in ${RETRY_DELAY}s..."
            sleep "$RETRY_DELAY"
        fi
        ((attempt++))
    done
    
    error "Failed to fetch server list after $MAX_RETRIES attempts"
    return 1
}

#=============================================================================
# Load Regions
#=============================================================================

load_regions() {
    step "Loading regions from $PROPERTIES_FILE"
    
    if [ ! -f "$PROPERTIES_FILE" ] || [ ! -s "$PROPERTIES_FILE" ]; then
        error "Regions file not found or empty: $PROPERTIES_FILE"
        return 1
    fi
    
    # Read and validate regions
    REGION_IDS=()
    local line_num=0
    
    while IFS= read -r region; do
        ((line_num++))
        
        # Skip empty lines and comments
        [[ -z "$region" || "$region" =~ ^[[:space:]]*# ]] && continue
        
        # Trim whitespace
        region=$(echo "$region" | tr -d '[:space:]')
        
        if validate_region_id "$region"; then
            REGION_IDS+=("$region")
            debug "Added region: $region"
        else
            warn "Line $line_num: Skipping invalid region: $region"
        fi
    done < "$PROPERTIES_FILE"
    
    if [ ${#REGION_IDS[@]} -eq 0 ]; then
        error "No valid regions found in $PROPERTIES_FILE"
        return 1
    fi
    
    success "Loaded ${#REGION_IDS[@]} region(s): ${REGION_IDS[*]}"
    return 0
}

#=============================================================================
# Ping Server
#=============================================================================

ping_server() {
    local server="$1"
    local ping_result
    
    debug "Pinging $server (count: $PING_COUNT, timeout: $PING_TIMEOUT)"
    
    # Use timeout command if available
    if command -v timeout >/dev/null 2>&1; then
        ping_result=$(timeout "$PING_TIMEOUT" ping -c "$PING_COUNT" -W 2 -q "$server" 2>/dev/null || echo "")
    else
        ping_result=$(ping -c "$PING_COUNT" -W 2 -q "$server" 2>/dev/null || echo "")
    fi
    
    if [ -z "$ping_result" ]; then
        debug "Ping failed for $server"
        echo "999999"
        return 1
    fi
    
    # Extract average ping time
    local avg_ping
    avg_ping=$(echo "$ping_result" | awk -F '/' 'END {print ($5 != "" ? $5 : "999999")}')
    
    # Validate it's a number
    if [[ "$avg_ping" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        debug "Ping result for $server: ${avg_ping}ms"
        echo "$avg_ping"
        return 0
    else
        debug "Invalid ping result for $server: $avg_ping"
        echo "999999"
        return 1
    fi
}

#=============================================================================
# Find Best Server
#=============================================================================

find_best_server() {
    local region="$1"
    
    step "Finding best server for region: $region"
    
    # Get WireGuard servers for this region
    local wg_servers_json
    wg_servers_json=$(echo "$SERVER_LIST" | jq -c --arg reg "$region" \
        '.regions[] | select(.id == $reg) | .servers.wg // empty')
    
    if [ -z "$wg_servers_json" ] || [ "$wg_servers_json" = "null" ]; then
        error "No WireGuard servers found for region: $region"
        debug "Available regions: $(echo "$SERVER_LIST" | jq -r '.regions[].id' | tr '\n' ' ')"
        return 1
    fi
    
    # Count servers
    local server_count
    server_count=$(echo "$wg_servers_json" | jq '. | length')
    info "Found $server_count WireGuard server(s) for $region"
    
    # Parse all servers
    local servers_data
    servers_data=$(echo "$wg_servers_json" | jq -r '.[] | "\(.ip)|\(.cn)"')
    
    if [ -z "$servers_data" ]; then
        error "Failed to parse server data for region: $region"
        return 1
    fi
    
    local best_server=""
    local best_ping=999999
    local best_host=""
    local tested=0
    local reachable=0
    
    while IFS='|' read -r ip hostname; do
        ((tested++))
        
        info "Testing server $tested/$server_count: $ip ($hostname)"
        
        local ping_time
        ping_time=$(ping_server "$ip")
        
        if [ "$ping_time" != "999999" ]; then
            ((reachable++))
            info "  ↳ Ping: ${ping_time}ms ✓"
            
            # Compare using bc for floating point
            if (( $(echo "$ping_time < $best_ping" | bc -l 2>/dev/null || echo 0) )); then
                best_ping="$ping_time"
                best_server="$ip"
                best_host="$hostname"
                debug "New best server: $best_server ($best_ping ms)"
            fi
        else
            warn "  ↳ Server unreachable ✗"
        fi
    done <<< "$servers_data"
    
    info "Tested: $tested servers, Reachable: $reachable servers"
    
    if [ -z "$best_server" ]; then
        error "No reachable servers found for region: $region"
        return 1
    fi
    
    success "Best server: $best_server ($best_host) - ${best_ping}ms"
    
    # Export results
    BEST_SERVER="$best_server"
    BEST_HOST="$best_host"
    BEST_PING="$best_ping"
    
    return 0
}

#=============================================================================
# Generate WireGuard Keys
#=============================================================================

generate_wg_keys() {
    step "Generating WireGuard key pair..."
    
    # Generate keys without writing to disk
    PRIVATE_KEY=$(wg genkey)
    PUBLIC_KEY=$(echo "$PRIVATE_KEY" | wg pubkey)
    
    if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
        error "Failed to generate WireGuard keys"
        return 1
    fi
    
    debug "Private key: ${PRIVATE_KEY:0:10}**** (length: ${#PRIVATE_KEY})"
    debug "Public key: ${PUBLIC_KEY:0:10}**** (length: ${#PUBLIC_KEY})"
    success "WireGuard keys generated"
    return 0
}

#=============================================================================
# Register Key with PIA (FIXED VERSION)
#=============================================================================

register_key() {
    local host="$1"
    local server="$2"
    local pubkey="$3"
    
    step "Registering WireGuard key with PIA server..."
    info "  Server: $host ($server)"
    debug "  Public Key: ${pubkey:0:20}..."
    debug "  Token: ${TOKEN:0:10}..."
    
    local url="https://$host:1337/addKey"
    debug "  API URL: $url"
    
    local attempt=1
    local response
    
    while [ $attempt -le "$MAX_RETRIES" ]; do
        info "Registration attempt $attempt of $MAX_RETRIES"
        
        # Use GET method with --data-urlencode (PIA's expected format)
        # The -G flag makes curl use GET even with --data
        response=$(curl -sf \
            --max-time 30 \
            --connect-to "$host::$server:" \
            --cacert "$CA_CERT" \
            -G \
            --data-urlencode "pt=$TOKEN" \
            --data-urlencode "pubkey=$pubkey" \
            "$url" 2>&1)
        
        local curl_exit=$?
        debug "Curl exit code: $curl_exit"
        
        if [ $curl_exit -eq 0 ] && [ -n "$response" ]; then
            debug "Response received (length: ${#response})"
            
            # Validate JSON
            if echo "$response" | jq -e . >/dev/null 2>&1; then
                local status
                status=$(echo "$response" | jq -r '.status // empty')
                debug "API Status: $status"
                
                if [ "$status" = "OK" ]; then
                    # Parse response
                    SERVER_KEY=$(echo "$response" | jq -r '.server_key // empty')
                    SERVER_PORT=$(echo "$response" | jq -r '.server_port // empty')
                    DNS_SERVERS=$(echo "$response" | jq -r '.dns_servers | join(", ") // empty')
                    PEER_IP=$(echo "$response" | jq -r '.peer_ip // empty')
                    
                    debug "Server Key: ${SERVER_KEY:0:20}..."
                    debug "Server Port: $SERVER_PORT"
                    debug "DNS Servers: $DNS_SERVERS"
                    debug "Peer IP: $PEER_IP"
                    
                    if [ -z "$SERVER_KEY" ] || [ -z "$SERVER_PORT" ] || [ -z "$PEER_IP" ]; then
                        error "Incomplete response from server"
                        debug "Full response: $response"
                    else
                        success "Key registered successfully"
                        info "  Server Port: $SERVER_PORT"
                        info "  Peer IP: $PEER_IP"
                        return 0
                    fi
                else
                    warn "Server returned non-OK status: $status"
                    debug "Full response: $response"
                    
                    # Check for specific error messages
                    local message
                    message=$(echo "$response" | jq -r '.message // empty')
                    if [ -n "$message" ]; then
                        error "Server message: $message"
                    fi
                fi
            else
                error "Invalid JSON response"
                debug "Response (first 500 chars): ${response:0:500}"
            fi
        else
            warn "Curl request failed (exit code: $curl_exit)"
            debug "Error output: $response"
            
            # Provide specific error messages
            case $curl_exit in
                6)  error "Could not resolve host: $host" ;;
                7)  error "Failed to connect to $server:1337" ;;
                28) error "Connection timeout" ;;
                35) error "SSL/TLS connection error" ;;
                51) error "SSL certificate verification failed" ;;
                52) error "Empty response from server" ;;
                *)  error "Unknown curl error: $curl_exit" ;;
            esac
        fi
        
        if [ $attempt -lt "$MAX_RETRIES" ]; then
            warn "Retrying in ${RETRY_DELAY}s..."
            sleep "$RETRY_DELAY"
        fi
        ((attempt++))
    done
    
    error "Failed to register key after $MAX_RETRIES attempts"
    return 1
}

#=============================================================================
# Generate Configuration File
#=============================================================================

generate_config() {
    local region="$1"
    local hostname="$2"
    local ping="$3"
    local server_ip="$4"
    
    step "Generating WireGuard configuration..."
    
    # Sanitize hostname for filename
    local safe_hostname
    safe_hostname=$(sanitize_filename "$hostname")
    
    # Round ping to integer
    local ping_int
    ping_int=$(printf "%.0f" "$ping")
    
    local config_file="./configs/pia-${region}-${safe_hostname}-${ping_int}ms.conf"
    debug "Config file: $config_file"
    
    mkdir -p "$(dirname "$config_file")"
    
    # Write config atomically
    local temp_file="${config_file}.tmp.$$"
    
    cat > "$temp_file" <<EOF
# PIA WireGuard Configuration
# Region: $region
# Server: $hostname ($server_ip)
# Ping: ${ping_int}ms
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
    
    # Set restrictive permissions
    chmod 600 "$temp_file"
    
    # Atomic move
    mv "$temp_file" "$config_file"
    
    # Verify config
    if [ -f "$config_file" ]; then
        local file_size
        file_size=$(stat -c%s "$config_file" 2>/dev/null || stat -f%z "$config_file" 2>/dev/null)
        success "Config generated: $config_file (${file_size} bytes)"
        return 0
    else
        error "Failed to create config file: $config_file"
        return 1
    fi
}

#=============================================================================
# Process Single Region
#=============================================================================

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
    
    success "Region $region completed successfully"
    
    # Clean up keys from memory
    unset PRIVATE_KEY PUBLIC_KEY SERVER_KEY
    
    return 0
}

#=============================================================================
# Main Execution
#=============================================================================

main() {
    log ""
    log "=============================================="
    log "=== PIA WireGuard Config Generator ==="
    log "=============================================="
    log "Started: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    log "Hostname: $(hostname)"
    log "Debug mode: $DEBUG"
    log "Max retries: $MAX_RETRIES"
    log "Retry delay: ${RETRY_DELAY}s"
    log "=============================================="
    log ""
    
    # Load credentials
    if ! load_credentials; then
        error "Failed to load credentials"
        exit 1
    fi
    
    # Download CA cert
    if ! download_ca_cert; then
        error "Failed to download CA certificate"
        exit 1
    fi
    
    # Authenticate
    if ! authenticate; then
        error "Failed to authenticate with PIA"
        exit 1
    fi
    
    # Clear credentials from memory after auth
    unset PIA_USER PIA_PASS
    debug "Credentials cleared from memory"
    
    # Fetch server list
    if ! fetch_server_list; then
        error "Failed to fetch server list"
        exit 1
    fi
    
    # Load regions
    if ! load_regions; then
        error "Failed to load regions"
        exit 1
    fi
    
    # Process each region
    local success_count=0
    local fail_count=0
    local failed_regions=()
    
    for region in "${REGION_IDS[@]}"; do
        if process_region "$region"; then
            ((success_count++))
        else
            ((fail_count++))
            failed_regions+=("$region")
            warn "Region $region failed, continuing with next region..."
        fi
    done
    
    log ""
    log "=============================================="
    log "=== Summary ==="
    log "=============================================="
    log "Total regions: ${#REGION_IDS[@]}"
    log "Successful: $success_count"
    log "Failed: $fail_count"
    
    if [ $fail_count -gt 0 ]; then
        log "Failed regions: ${failed_regions[*]}"
    fi
    
    log "Completed: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    log "=============================================="
    log ""
    
    if [ $fail_count -gt 0 ]; then
        if [ $success_count -gt 0 ]; then
            warn "Some regions failed, but $success_count succeeded"
            exit 0  # Partial success
        else
            error "All regions failed"
            exit 1
        fi
    fi
    
    success "All regions processed successfully!"
    exit 0
}

# Run main function
main "$@"