#!/bin/bash
set -euo pipefail
umask 077
ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/settings.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"

export PIA_USER='test-user'
export PIA_PASS=$' spaces " quotes \' $(touch injected) `touch injected` \\ dollar$\ntrailing\n\n'
export UNIFI_PASS="$PIA_PASS" CONFIG_DIR='/configs/custom directory'
expected=$PIA_PASS
persist_settings settings.json
unset PIA_PASS UNIFI_PASS CONFIG_DIR
load_settings settings.json
[[ "$PIA_PASS" == "$expected" && "$UNIFI_PASS" == "$expected" ]]
[[ "$CONFIG_DIR" == '/configs/custom directory' && ! -e injected ]]
[[ $(stat -c '%a' settings.json) == 600 ]]
jq '. + {BASH_ENV: "evil", PATH: "evil", SHELLOPTS: "evil"}' settings.json > unknown.json
old_path=$PATH
load_settings unknown.json
[[ "$PATH" == "$old_path" ]]
printf '%s\n' '{"PIA_PASS":42}' > invalid.json
if load_settings invalid.json; then echo 'Accepted invalid settings' >&2; exit 1; fi
printf '%s\n' '{"PIA_PASS":"nul\u0000byte"}' > invalid.json
if load_settings invalid.json; then echo 'Accepted NUL byte' >&2; exit 1; fi

# Exercise the real UniFi request builder with mocked network responses.
mkdir bin
cat > bin/curl <<'MOCK'
#!/bin/bash
printf '%s\n' "$@" >> "$CURL_ARGS"
if [[ "$*" == *'/api/auth/login'* ]]; then
  while (($#)); do
    if [[ "$1" == '-c' ]]; then printf 'TOKEN\n' > "$2"; break; fi
    shift
  done
  printf 'HTTP/1.1 200 OK\r\nX-CSRF-Token: csrf-test\r\n\r\n'
else
  printf '{"meta":{"rc":"ok"},"data":[]}'
fi
MOCK
chmod +x bin/curl
export PATH="$work/bin:$PATH" CURL_ARGS="$work/curl-args"
export PUSH_TO_UNIFI=1 UNIFI_URL=https://controller.example UNIFI_USER=test UNIFI_REGION_MAP=uk=Test
export LOG_FILE="$work/unifi.log"
bash "$ROOT/unifi-push.sh" >/dev/null
! grep -qx -- '--insecure' "$CURL_ARGS"
grep -qx -- '--max-time' "$CURL_ARGS"
grep -qx -- 'X-Csrf-Token: csrf-test' "$CURL_ARGS"
: > "$CURL_ARGS"
UNIFI_CA_CERT=/test/controller-ca.pem bash "$ROOT/unifi-push.sh" >/dev/null
grep -qx -- '--cacert' "$CURL_ARGS"
grep -qx -- '/test/controller-ca.pem' "$CURL_ARGS"
: > "$CURL_ARGS"
UNIFI_INSECURE=1 bash "$ROOT/unifi-push.sh" >/dev/null
grep -qx -- '--insecure' "$CURL_ARGS"
: > "$CURL_ARGS"
UNIFI_URL=http://controller.example bash "$ROOT/unifi-push.sh" >/dev/null
[[ ! -s "$CURL_ARGS" ]]
echo 'Security regression checks passed'
