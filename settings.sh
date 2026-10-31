#!/bin/bash
# Trusted code only: settings files themselves are JSON, never shell code.
load_settings() {
    local file="$1" name value
    jq -e 'type == "object" and all(.[]; type == "string" and (contains("\u0000") | not))' "$file" >/dev/null || return 1
    for name in PIA_USER PIA_PASS PUSH_TO_UNIFI UNIFI_URL UNIFI_SITE UNIFI_REGION_MAP UNIFI_USER UNIFI_PASS UNIFI_CA_CERT UNIFI_INSECURE CONFIG_DIR DEBUG PIA_SERVER_LIST_URL; do
        if jq -e --arg name "$name" 'has($name)' "$file" >/dev/null; then
            # A sentinel preserves trailing newlines through command substitution.
            value=$(jq -jr --arg name "$name" '.[$name], "x"' "$file") || return 1
            printf -v "$name" '%s' "${value%x}"
            export "$name"
        fi
    done
}

persist_settings() {
    local file="$1" temporary
    temporary=$(mktemp "${file}.XXXXXX") || return 1
    if ! jq -n 'env | {PIA_USER: (.PIA_USER // ""), PIA_PASS: (.PIA_PASS // ""),
        PUSH_TO_UNIFI: (.PUSH_TO_UNIFI // "0"), UNIFI_URL: (.UNIFI_URL // ""),
        UNIFI_SITE: (.UNIFI_SITE // "default"), UNIFI_REGION_MAP: (.UNIFI_REGION_MAP // ""),
        UNIFI_USER: (.UNIFI_USER // ""), UNIFI_PASS: (.UNIFI_PASS // ""),
        UNIFI_CA_CERT: (.UNIFI_CA_CERT // ""), UNIFI_INSECURE: (.UNIFI_INSECURE // "0"),
        CONFIG_DIR: (.CONFIG_DIR // "/configs"), DEBUG: (.DEBUG // "0"),
        PIA_SERVER_LIST_URL: (.PIA_SERVER_LIST_URL // "https://serverlist.piaservers.net/vpninfo/servers/v6")}' > "$temporary"; then
        rm -f "$temporary"
        return 1
    fi
    chmod 600 "$temporary" && mv -f "$temporary" "$file"
}
