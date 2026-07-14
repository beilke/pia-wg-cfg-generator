#!/bin/bash
# unifi-push.sh — push freshly generated PIA WireGuard configs to UniFi VPN client networks.
#
# The UniFi controller stores WireGuard client profiles as the full .conf file
# content inside the networkconf object (wireguard_client_mode: "file").
# This script logs into the UniFi OS console, matches each generated
# pia-<region>-*.conf to its UniFi network by name, and PUTs the new config.
#
# Configuration (env or /app/unifi.env written by the entrypoint):
#   PUSH_TO_UNIFI     "1" to enable (anything else = no-op)
#   UNIFI_URL         e.g. https://192.168.1.1  (UniFi OS console, self-signed cert)
#   UNIFI_USER        local admin username (not SSO)
#   UNIFI_PASS        local admin password
#   UNIFI_SITE        controller site (default: default)
#   UNIFI_REGION_MAP  comma list of <region>=<UniFi network name>, e.g.
#                     br=PIA-VPN-Brazil,uk=PIA-VPN-London
#   CONFIG_DIR        where the generated .conf files live (default: /configs)
#
# Always exits 0 — a push failure must never break config generation/cron.

LOG_FILE="${LOG_FILE:-/logs/unifi-push.log}"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - unifi-push: $1" | tee -a "$LOG_FILE"
}

# Load settings persisted by the entrypoint (cron jobs don't inherit full env)
if [ -f /app/unifi.env ]; then
  # shellcheck disable=SC1091
  . /app/unifi.env
fi

if [ "${PUSH_TO_UNIFI:-0}" != "1" ]; then
  log "PUSH_TO_UNIFI is not 1 — skipping UniFi push"
  exit 0
fi

CONFIG_DIR="${CONFIG_DIR:-/configs}"
UNIFI_SITE="${UNIFI_SITE:-default}"

for var in UNIFI_URL UNIFI_USER UNIFI_PASS UNIFI_REGION_MAP; do
  eval "val=\${$var:-}"
  if [ -z "$val" ]; then
    log "ERROR: $var is not set — cannot push to UniFi"
    exit 0
  fi
done

COOKIE_JAR="$(mktemp /tmp/unifi-cookies.XXXXXX)"
cleanup() { rm -f "$COOKIE_JAR"; }
trap cleanup EXIT

# ---------------------------------------------------------------------------
# 1. Login (UniFi OS: POST /api/auth/login, grab session cookie + CSRF token)
# ---------------------------------------------------------------------------
login_payload="$(jq -n --arg u "$UNIFI_USER" --arg p "$UNIFI_PASS" '{username:$u, password:$p}')"

login_headers="$(curl -sk -c "$COOKIE_JAR" -D - -o /dev/null \
  -H 'Content-Type: application/json' \
  -d "$login_payload" \
  "$UNIFI_URL/api/auth/login")"

CSRF_TOKEN="$(printf '%s' "$login_headers" | tr -d '\r' | awk 'tolower($1)=="x-csrf-token:"{print $2; exit}')"

if ! grep -qi 'TOKEN' "$COOKIE_JAR"; then
  log "ERROR: UniFi login failed (no session cookie) — check UNIFI_USER/UNIFI_PASS"
  exit 0
fi
log "Logged in to $UNIFI_URL (csrf: $([ -n "$CSRF_TOKEN" ] && echo yes || echo no))"

# ---------------------------------------------------------------------------
# 2. Fetch all network configs once
# ---------------------------------------------------------------------------
networks_json="$(curl -sk -b "$COOKIE_JAR" \
  ${CSRF_TOKEN:+-H "X-Csrf-Token: $CSRF_TOKEN"} \
  "$UNIFI_URL/proxy/network/api/s/$UNIFI_SITE/rest/networkconf")"

if [ "$(printf '%s' "$networks_json" | jq -r '.meta.rc // empty' 2>/dev/null)" != "ok" ]; then
  log "ERROR: failed to fetch networkconf list from controller"
  exit 0
fi

# ---------------------------------------------------------------------------
# 3. Push each region's newest config
# ---------------------------------------------------------------------------
pushed=0
failed=0
skipped=0

OLD_IFS="$IFS"
IFS=','
for mapping in $UNIFI_REGION_MAP; do
  IFS="$OLD_IFS"
  region="${mapping%%=*}"
  netname="${mapping#*=}"

  if [ -z "$region" ] || [ -z "$netname" ] || [ "$region" = "$netname" ]; then
    log "WARNING: bad mapping entry '$mapping' — expected <region>=<network name>"
    skipped=$((skipped + 1))
    IFS=','
    continue
  fi

  # Newest generated config for this region
  conf_file="$(ls -t "$CONFIG_DIR"/pia-"$region"-*.conf 2>/dev/null | head -1)"
  if [ -z "$conf_file" ]; then
    log "WARNING: no config file found for region '$region' (pattern: pia-$region-*.conf) — skipping"
    skipped=$((skipped + 1))
    IFS=','
    continue
  fi

  net_id="$(printf '%s' "$networks_json" | jq -r --arg n "$netname" \
    '.data[] | select(.name == $n and .purpose == "vpn-client") | ._id' | head -1)"
  if [ -z "$net_id" ]; then
    # Network doesn't exist yet — try to create it (POST rest/networkconf)
    log "No vpn-client network named '$netname' — attempting to create it"
    wg_addr="$(awk -F'= *' '/^[Aa]ddress/{print $2; exit}' "$conf_file" | tr -d ' \r')"
    case "$wg_addr" in */*) ;; *) wg_addr="${wg_addr}/32" ;; esac
    create_body="$(jq -n --rawfile conf "$conf_file" \
      --arg fn "$(basename "$conf_file")" \
      --arg name "$netname" \
      --arg subnet "$wg_addr" \
      '{name: $name, purpose: "vpn-client", vpn_type: "wireguard-client",
        enabled: true, wireguard_client_mode: "file",
        wireguard_client_configuration_file: $conf,
        wireguard_client_configuration_filename: $fn,
        ip_subnet: $subnet, mss_clamp: "auto",
        interface_mtu: 1420, interface_mtu_enabled: false}')"
    create_resp="$(curl -sk -b "$COOKIE_JAR" -X POST \
      -H 'Content-Type: application/json' \
      ${CSRF_TOKEN:+-H "X-Csrf-Token: $CSRF_TOKEN"} \
      -d "$create_body" \
      "$UNIFI_URL/proxy/network/api/s/$UNIFI_SITE/rest/networkconf")"
    create_rc="$(printf '%s' "$create_resp" | jq -r '.meta.rc // empty' 2>/dev/null)"
    if [ "$create_rc" = "ok" ]; then
      log "OK: created vpn-client network '$netname' <- $(basename "$conf_file")"
      pushed=$((pushed + 1))
    else
      create_msg="$(printf '%s' "$create_resp" | jq -r '.meta.msg // empty' 2>/dev/null)"
      log "WARNING: could not create network '$netname' (${create_msg:-no error message}) — create it once in the UniFi UI. Response: $(printf '%.200s' "$create_resp")"
      skipped=$((skipped + 1))
    fi
    IFS=','
    continue
  fi

  body="$(jq -n --rawfile conf "$conf_file" --arg fn "$(basename "$conf_file")" \
    '{wireguard_client_configuration_file: $conf, wireguard_client_configuration_filename: $fn}')"

  resp="$(curl -sk -b "$COOKIE_JAR" -X PUT \
    -H 'Content-Type: application/json' \
    ${CSRF_TOKEN:+-H "X-Csrf-Token: $CSRF_TOKEN"} \
    -d "$body" \
    "$UNIFI_URL/proxy/network/api/s/$UNIFI_SITE/rest/networkconf/$net_id")"

  rc="$(printf '%s' "$resp" | jq -r '.meta.rc // empty' 2>/dev/null)"
  if [ "$rc" = "ok" ]; then
    log "OK: $netname <- $(basename "$conf_file")"
    pushed=$((pushed + 1))
  else
    msg="$(printf '%s' "$resp" | jq -r '.meta.msg // empty' 2>/dev/null)"
    log "ERROR: PUT failed for $netname (${msg:-no error message}) — response: $(printf '%.200s' "$resp")"
    failed=$((failed + 1))
  fi
  IFS=','
done
IFS="$OLD_IFS"

log "Done: $pushed pushed, $failed failed, $skipped skipped"
exit 0
