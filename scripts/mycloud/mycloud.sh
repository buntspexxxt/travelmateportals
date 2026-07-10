#!/bin/bash
# SCRIPT_VERSION="1.1.0"

trap 'rm -f "${COOKIE_JAR:-}" "${COOKIE_FILE:-}" "${HTML_FILE:-}" "${REG_PAGE:-}"' EXIT
LOG_FILE="/tmp/portal_log.txt"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE=$(mktemp)
REG_PAGE=$(mktemp)

echo "Starting portal login sequence..." | tee -a "$LOG_FILE"

echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        break
    fi
    sleep 1
done

echo "Fetching initial landing page..." | tee -a "$LOG_FILE"
curl -m 15 -k -A "$USER_AGENT" -L -c "$COOKIE_FILE" -o "$REG_PAGE" "http://neverssl.com" > /dev/null 2>&1

echo "Extracting registration form data..." | tee -a "$LOG_FILE"
# The portal uses a POST to /service-platform/macauthlogin/v5/registration
# It usually requires no complex parameters besides just the POST request to trigger the auth
# Based on the HTML, it's a simple one-click form

RESPONSE_CODE=$(curl -m 15 -k -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -L -d "" -w "%{http_code}" -o /dev/null "https://service.thecloud.eu/service-platform/macauthlogin/v5/registration")
echo "HTTP Registration Response: $RESPONSE_CODE" | tee -a "$LOG_FILE"

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -m 15 -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)"
    exit 1
fi