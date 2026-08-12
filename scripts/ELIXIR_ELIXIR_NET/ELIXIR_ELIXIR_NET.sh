#!/bin/sh
# SCRIPT_VERSION="1.1.0"

LOG_FILE="/tmp/portal_login.log"
trap 'rm -f "$COOKIE_FILE" "$HTML_OUT"' EXIT
COOKIE_FILE=$(mktemp)
HTML_OUT=$(mktemp)

echo "Starting Login Script..." | tee -a "$LOG_FILE"

# Wait for network
echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 20 ]; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
    i=$((i + 1))
done

# Extract gateway IP as a fallback
GATEWAY_IP=$(ip route | grep default | awk '{print $3}')
if [ -z "$GATEWAY_IP" ]; then
    GATEWAY_IP=$(route -n | grep '^0.0.0.0' | awk '{print $2}')
fi
echo "Gateway IP detected: $GATEWAY_IP" | tee -a "$LOG_FILE"

# Define default target URL
TARGET_URL="http://ELIXIR.NET/login"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# Check if ELIXIR.NET resolves
if ! nslookup ELIXIR.NET >/dev/null 2>&1; then
    echo "WARNING: ELIXIR.NET does not resolve. Using Gateway IP instead." | tee -a "$LOG_FILE"
    if [ -n "$GATEWAY_IP" ]; then
        TARGET_URL="http://${GATEWAY_IP}/login"
    fi
fi

echo "Fetching login page from $TARGET_URL..." | tee -a "$LOG_FILE"
curl -k -A "$USER_AGENT" -c "$COOKIE_FILE" -o "$HTML_OUT" -m 15 -w "HTTP Status: %{http_code}
" "$TARGET_URL" | tee -a "$LOG_FILE"

echo "Parsing login HTML for CHAP parameters..." | tee -a "$LOG_FILE"
# Extract CHAP_ID and CHALLENGE
CHAP_ID=$(sed -n "s/.*hexMD5('\([^']*\)'.*/\1/p" "$HTML_OUT" | tr -d '\015')
CHALLENGE=$(sed -n "s/.*password\.value + '\([^']*\)'.*/\1/p" "$HTML_OUT" | tr -d '\015')

echo "Extracted CHAP_ID: $CHAP_ID" | tee -a "$LOG_FILE"
echo "Extracted CHALLENGE: $CHALLENGE" | tee -a "$LOG_FILE"

if [ -z "$CHAP_ID" ] || [ -z "$CHALLENGE" ]; then
    echo "ERROR: Failed to extract CHAP credentials from HTML." | tee -a "$LOG_FILE"
    exit 1
fi

# Retrieve default inputs if present
DST=$(sed -n 's/.*name="dst" value="\([^"]*\)".*/\1/p' "$HTML_OUT" | head -n 1 | tr -d '\015')
POPUP=$(sed -n 's/.*name="popup" value="\([^"]*\)".*/\1/p' "$HTML_OUT" | head -n 1 | tr -d '\015')
USERNAME=$(sed -n 's/.*name="username" value="\([^"]*\)".*/\1/p' "$HTML_OUT" | head -n 1 | tr -d '\015')

[ -z "$DST" ] && DST="http://detectportal.firefox.com/success.txt"
[ -z "$POPUP" ] && POPUP="true"
PASSWORD=""

echo "Computing MD5 Hash..." | tee -a "$LOG_FILE"
MD5_HASH=$( (printf "%b" "$CHAP_ID"; printf "%s" "$PASSWORD"; printf "%b" "$CHALLENGE") | md5sum | awk '{print $1}' )
echo "Computed MD5 Hash: $MD5_HASH" | tee -a "$LOG_FILE"

echo "Submitting MikroTik CHAP login request..." | tee -a "$LOG_FILE"
curl -k -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -o "$HTML_OUT" -m 15 -w "HTTP Status: %{http_code}
" \
    --data-urlencode "username=$USERNAME" \
    --data-urlencode "password=$MD5_HASH" \
    --data-urlencode "dst=$DST" \
    --data-urlencode "popup=$POPUP" \
    "$TARGET_URL" | tee -a "$LOG_FILE"

echo "Verifying real Internet connectivity (polling for up to 40 seconds)..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
    if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
        echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
        exit 0
    fi
    echo "Attempt $i: Not connected yet (HTTP Check Code: $CHECK_CODE). Waiting..." | tee -a "$LOG_FILE"
    sleep 4
    i=$((i + 1))
done

echo "ERROR: Portal request completed but no Internet connectivity established after 40 seconds." | tee -a "$LOG_FILE"
exit 1