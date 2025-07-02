#!/bin/bash
# WireGuard PIA Multi-Config Debug Script
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
WG_DIR="/etc/wireguard"

# Check root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Error: Run as root (sudo).${NC}"
    exit 1
fi

if [ $# -eq 0 ]; then
    echo -e "${RED}Usage: $0 <file.conf> or $0 *.conf${NC}"
    exit 1
fi

# Create simplified filename for PIA configs
create_valid_filename() {
    local original=$(basename "$1")
    # Extract country code (e.g., 'de' from 'pia-de_berlin...')
    local country_code=$(echo "$original" | grep -o 'pia-[a-z]\{2\}' | cut -d- -f2)
    # If no country code found, use generic name
    [ -z "$country_code" ] && country_code="vpn"
    echo "pia_${country_code}.conf"
}

# Process each configuration file
process_config() {
    local CONFIG_SOURCE="$1"
    local ORIGINAL_NAME=$(basename "$CONFIG_SOURCE")
    local VALID_NAME=$(create_valid_filename "$ORIGINAL_NAME")
    local TARGET_CONF="$WG_DIR/$VALID_NAME"

    echo -e "\n${YELLOW}=== Processing: $ORIGINAL_NAME ===${NC}"
    echo -e "Will use interface name: ${GREEN}${VALID_NAME%.*}${NC}"

    # Validate .conf extension
    if [[ "$ORIGINAL_NAME" != *.conf ]]; then
        echo -e "${RED}Skipping: Not a .conf file${NC}"
        return 1
    fi

    # Backup existing config
    if [ -f "$TARGET_CONF" ]; then
        BACKUP="$TARGET_CONF.bak-$(date +%s)"
        echo -e "${YELLOW}Backing up existing config to $BACKUP${NC}"
        cp "$TARGET_CONF" "$BACKUP" || return 1
    fi

    # Copy config with new name
    echo -e "[1] Installing to $WG_DIR as $VALID_NAME..."
    if ! cp "$CONFIG_SOURCE" "$TARGET_CONF"; then
        echo -e "${RED}Copy failed!${NC}"
        return 1
    fi
    chmod 600 "$TARGET_CONF"

    # Validate syntax
    echo -e "[2] Validating syntax..."
    if wg-quick up "$TARGET_CONF" >/dev/null 2>&1; then
        echo -e "${GREEN}Syntax OK.${NC}"
        echo -e "[3] Testing connection (3 seconds)..."
        wg-quick up "$TARGET_CONF"
        sleep 3
        echo -e "\n${YELLOW}Connection Status:${NC}"
        wg show "${VALID_NAME%.*}"
        wg-quick down "$TARGET_CONF"
        echo -e "\n${GREEN}Success! Use: sudo wg-quick up ${VALID_NAME%.*}${NC}"
    else
        echo -e "${RED}Syntax error! Details:${NC}"
        wg-quick up "$TARGET_CONF"
        return 1
    fi
}

# Process all input files
for CONFIG_PATH in "$@"; do
    # Skip directories
    [ -d "$CONFIG_PATH" ] && continue
    
    # Process regular files
    if [ -f "$CONFIG_PATH" ]; then
        process_config "$CONFIG_PATH"
    else
        echo -e "${YELLOW}Skipping: Not a file - $CONFIG_PATH${NC}"
    fi
done

echo -e "\n${GREEN}All configurations processed.${NC}"