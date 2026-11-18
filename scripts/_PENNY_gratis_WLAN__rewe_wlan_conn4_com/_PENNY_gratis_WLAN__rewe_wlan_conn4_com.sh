#!/bin/sh
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_login.log"
echo "Starting REWE/Conn4 portal login..." | tee -a "$LOG_FILE"

trap 'rm -f "$COOKIE_FILE" "$HTML_OUT" "$TMP_JSON"' EXIT

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

COOKIE_FILE=$(mktemp)
HTML_OUT=$(mktemp)
TMP_JSON=$(mktemp)
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Fetching portal landing to initialize session..." | tee -a "$LOG_FILE"
curl -k -L -A "$USER_AGENT" -c "$COOKIE_FILE" -o "$HTML_OUT" -m 15 "http://neverssl.com" > /dev/null 2>&1

echo "Extracting wbsToken..." | tee -a "$LOG_FILE"
# Extracting the wbsToken JSON object from the script block in HTML
TOKEN_JSON=$(sed -n 's/.*conn4.hotspot.wbsToken = \({.*}\);.*/\1/p' "$HTML_OUT" | tr -d '\015')

if [ -z "$TOKEN_JSON" ]; then
    echo "Error: Could not extract wbsToken JSON." | tee -a "$LOG_FILE"
    exit 1
fi

echo "$TOKEN_JSON" > "$TMP_JSON"
TOKEN=$(sed -n 's/.*"token":"\([a-zA-Z0-9+/=]\{50,\}\)".*/\1/p' "$TMP_JSON")

echo "Submitting authentication token to return endpoint..." | tee -a "$LOG_FILE"
# Using the return endpoint identified in the HTML
RETURN_URL="https://rewe-wlan.conn4.com/wbs/de/roaming/return/"
RESPONSE_CODE=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -o /dev/null -w "%{http_code}" --data-urlencode "token=$TOKEN" -m 15 "$RETURN_URL")

echo "HTTP Response: $RESPONSE_CODE" | tee -a "$LOG_FILE"

# Conn4 often requires a secondary fetch to confirm access
echo "Performing final session validation..." | tee -a "$LOG_FILE"
curl -k -A "$USER_AGENT" -b "$COOKIE_FILE" -o /dev/null -m 15 "https://rewe-wlan.conn4.com/" > /dev/null 2>&1

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