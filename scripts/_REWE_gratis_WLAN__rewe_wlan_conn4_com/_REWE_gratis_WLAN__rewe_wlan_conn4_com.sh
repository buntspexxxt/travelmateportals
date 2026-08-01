#!/bin/sh
# SCRIPT_VERSION="1.0.0"

LOG_FILE="/tmp/wifi_login.log"
COOKIE_JAR="/tmp/cookies.txt"
HTML_OUT="/tmp/portal_html.tmp"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

trap 'rm -f "$COOKIE_JAR" "$HTML_OUT"' EXIT

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

echo "Fetching portal index to initialize session..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -k -L -A "$USER_AGENT" -c "$COOKIE_JAR" -b "$COOKIE_JAR" -w "%\{url_effective}" -o "$HTML_OUT" -m 15 "https://rewe-wlan.conn4.com/")

echo "Extracting WBS Token from HTML..." | tee -a "$LOG_FILE"
HTML_CONTENT=$(cat "$HTML_OUT")
# Extract the JSON object from conn4.hotspot.wbsToken
WBS_TOKEN_JSON=$(echo "$HTML_CONTENT" | sed -n 's/.*conn4.hotspot.wbsToken = \({.*}\);.*/\1/p')

if [ -z "$WBS_TOKEN_JSON" ]; then
    echo "Error: Failed to find wbsToken in portal HTML." | tee -a "$LOG_FILE"
    exit 1
fi

# Using standard shell to extract values. Since no jq is assumed, we perform simple extraction
# Extract base64 token
TOKEN=$(echo "$WBS_TOKEN_JSON" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')

echo "Attempting to post the wbsToken to the login endpoint..." | tee -a "$LOG_FILE"
# Based on portal structure, we send a POST with the token to complete the flow
RESPONSE=$(curl -k -v -A "$USER_AGENT" -c "$COOKIE_JAR" -b "$COOKIE_JAR" -X POST \
    -H "Content-Type: application/json" \
    -d "{"token":"$TOKEN"}" \
    -m 15 "https://rewe-wlan.conn4.com/admon-assets/log.php?channel=clienterror" 2>&1)

echo "Verifying real Internet connectivity (polling for up to 40 seconds)..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%\{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
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