#!/bin/sh
# SCRIPT_VERSION="1.0.0"

LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE=$(mktemp)
HTML_FILE=$(mktemp)
POST_RESPONSE_FILE=$(mktemp)
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

trap 'rm -f "$COOKIE_FILE" "$HTML_FILE" "$POST_RESPONSE_FILE"' EXIT

echo "Starting Telekom Hotspot automated login..." | tee -a "$LOG_FILE"

echo "Waiting for network..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 20 ]; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network ready." | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
    i=$((i + 1))
done

echo "Fetching initial portal page..." | tee -a "$LOG_FILE"
curl -k -L -c "$COOKIE_FILE" -b "$COOKIE_FILE" -A "$USER_AGENT" -m 15 -o "$HTML_FILE" "http://neverssl.com"

# Extract base URL and trigger free login flow
# The portal requires a POST to the rest API for free access.
API_ENDPOINT="https://hotspot.t-mobile.net/wlan/rest/freeLogin"
echo "Submitting POST to $API_ENDPOINT" | tee -a "$LOG_FILE"

# Free Login Payload based on known Telekom Hotspot API structure
curl -k -X POST -c "$COOKIE_FILE" -b "$COOKIE_FILE" -A "$USER_AGENT" -m 15 \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -H "Referer: https://hotspot.t-mobile.net/" \
    --data-urlencode "UserName=" \
    --data-urlencode "Password=" \
    --data-urlencode "FNAME=0" \
    --data-urlencode "button=Login" \
    --data-urlencode "OriginatingServer=http://neverssl.com" \
    -o "$POST_RESPONSE_FILE" "$API_ENDPOINT"

RESPONSE=$(cat "$POST_RESPONSE_FILE")
echo "Login response received." | tee -a "$LOG_FILE"

# Polling for connectivity
echo "Verifying real Internet connectivity (polling for up to 40 seconds)..."
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
    if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
        echo "SUCCESS: Internet connection verified!"
        exit 0
    fi
    echo "Attempt $i: Not connected yet (HTTP Check Code: $CHECK_CODE). Waiting..."
    sleep 4
    i=$((i + 1))
done

echo "ERROR: Portal request completed but no Internet connectivity established after 40 seconds." | tee -a "$LOG_FILE"
exit 1