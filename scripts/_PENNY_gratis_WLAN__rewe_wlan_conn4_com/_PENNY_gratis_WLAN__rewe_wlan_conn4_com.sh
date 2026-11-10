#!/bin/sh
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_login.log"
echo "Starting REWE/Conn4 portal login..." | tee -a "$LOG_FILE"

trap 'rm -f "$COOKIE_FILE" "$HTML_OUT" "$TMP_JSON"' EXIT
i=1
while [ $i -le 20 ]; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network ready." | tee -a "$LOG_FILE"
        break
    fi
    sleep 1
    i=$((i + 1))
done

COOKIE_FILE=$(mktemp)
HTML_OUT=$(mktemp)
TMP_JSON=$(mktemp)
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Fetching portal landing..." | tee -a "$LOG_FILE"
curl -k -L -A "$USER_AGENT" -c "$COOKIE_FILE" -o "$HTML_OUT" -m 15 "http://neverssl.com" > /dev/null 2>&1

# Dynamically extract the wbsToken object from the JS variable in HTML
# The structure is conn4.hotspot.wbsToken = {"token":"..."...}
TOKEN_JSON=$(sed -n 's/.*conn4.hotspot.wbsToken = \({.*}\);.*/\1/p' "$HTML_OUT" | sed 's/\r//g')

if [ -z "$TOKEN_JSON" ]; then
    echo "Error: Could not extract wbsToken JSON." | tee -a "$LOG_FILE"
    exit 1
fi
echo "$TOKEN_JSON" > "$TMP_JSON"

# Extract the base64 token string
TOKEN=$(sed -n 's/.*"token":"\([a-zA-Z0-9+/=]\{50,\}\)".*/\1/p' "$TMP_JSON")

echo "Extracted Token: $TOKEN" | tee -a "$LOG_FILE"

# Conn4 portals require a post to the WBS return endpoint which initializes the session
# This follows the WISPAccessGatewayParam structure provided in the HTML
RETURN_URL="https://rewe-wlan.conn4.com/wbs/de/roaming/return/"

echo "Submitting token to return endpoint..." | tee -a "$LOG_FILE"
RESPONSE_CODE=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -o /dev/null -w "%{http_code}" -d "token=$TOKEN" -m 15 "$RETURN_URL")
echo "HTTP Response: $RESPONSE_CODE" | tee -a "$LOG_FILE"

# Final connectivity check
echo "Verifying real Internet connectivity (polling for up to 40 seconds)..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
    if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
        echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
        exit 0
    fi
    echo "Attempt $i: Not connected yet (HTTP Check Code: $CHECK_CODE)." | tee -a "$LOG_FILE"
    sleep 4
    i=$((i + 1))
done

echo "ERROR: Connection not established." | tee -a "$LOG_FILE"
exit 1