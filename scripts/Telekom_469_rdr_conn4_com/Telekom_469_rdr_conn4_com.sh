#!/bin/sh
# SCRIPT_VERSION="1.0.0"

trap 'rm -f "$COOKIE_FILE" "$HTML_FILE"' EXIT
COOKIE_FILE=$(mktemp)
HTML_FILE=$(mktemp)
LOG_FILE="/tmp/portal_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Starting connection check..." | tee -a "$LOG_FILE"

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

echo "Fetching portal landing page..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -k -L -A "$USER_AGENT" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -w "%{url_effective}" -o "$HTML_FILE" "http://neverssl.com")
echo "Effective URL: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

echo "Extracting WBS Token from HTML..." | tee -a "$LOG_FILE"
HTML_CONTENT=$(cat "$HTML_FILE")

# Extract the JSON object from the script tag content using sed
WBS_JSON=$(echo "$HTML_CONTENT" | sed -n 's/.*conn4.hotspot.wbsToken = \({.*}\);.*/\1/p')

if [ -z "$WBS_JSON" ]; then
    echo "Error: Could not extract WBS token. Portal might be fully dynamic or already logged in." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Extracted Token JSON: $WBS_JSON" | tee -a "$LOG_FILE"

# Extract base domain from current URL
BASE_URL=$(echo "$EFFECTIVE_URL" | cut -d'/' -f1-3)
echo "Base URL: $BASE_URL" | tee -a "$LOG_FILE"

# The portal logic uses a POST to a /wbs/ endpoint with the token
# Usually identified as a 'grant' process
GRANT_URL="$BASE_URL/wbs/de/roaming/return/"

echo "Submitting token to $GRANT_URL..." | tee -a "$LOG_FILE"
RESPONSE_CODE=$(curl -k -v -A "$USER_AGENT" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -o /dev/null -w "%{http_code}" -m 15 \
    -d "payload=$(echo "$WBS_JSON" | sed 's/"/\"/g')" \
    "$GRANT_URL")

echo "HTTP Response Code: $RESPONSE_CODE" | tee -a "$LOG_FILE"

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