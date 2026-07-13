#!/bin/sh

# Auto-injected cleanup trap for temporary session files
trap 'rm -f "${COOKIE_JAR:-}" "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_login.log"
echo "Starting login process" > "$LOG_FILE"

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

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE=$(mktemp)

echo "Fetching landing page to get session..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -k -v -L -A "$USER_AGENT" -c "$COOKIE_FILE" -m 15 -w "%{http_code}" -o /tmp/portal_home.html "http://neverssl.com")
echo "HTTP Response: $RESPONSE" | tee -a "$LOG_FILE"

echo "Extracting 'Get Online' link..." | tee -a "$LOG_FILE"
GET_ONLINE_URL=$(grep -o 'https://service.thecloud.eu/service-platform/url/[0-9]*' /tmp/portal_home.html | head -n 1 | sed "s/\r//g")

if [ -n "$GET_ONLINE_URL" ]; then
    echo "Navigating to: $GET_ONLINE_URL" | tee -a "$LOG_FILE"
    curl -k -v -L -A "$USER_AGENT" -b "$COOKIE_FILE" -m 15 -o /dev/null "$GET_ONLINE_URL" | tee -a "$LOG_FILE"
else
    echo "ERROR: Could not find Get Online URL" | tee -a "$LOG_FILE"
    exit 1
fi

echo "Verifying real Internet connectivity..." | tee -a "$LOG_FILE"
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    exit 1
fi