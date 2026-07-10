#!/bin/bash
# SCRIPT_VERSION="1.4.0"
trap 'rm -f "${COOKIE_FILE:-}" "${LOG_FILE:-}"' EXIT
LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE=$(mktemp)
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Starting RRX Hotspot Portal Login Process..." | tee -a "$LOG_FILE"

echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
done

perform_curl() {
    curl -m 15 -k -v -L -A "$USER_AGENT" -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$@"
}

echo "Step 1: Identifying redirect parameters..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -m 15 -k -L -A "$USER_AGENT" -o /dev/null -w "%{url_effective}" "http://neverssl.com")
# Extract query params from loginurl field to build Hotsplots auth URL
QUERY_STRING=$(echo "$EFFECTIVE_URL" | sed -n 's/.*loginurl=https%3A%2F%2Fwww.hotsplots.de%2Fauth%2Flogin.php%3F\(.*\)/\1/p' | sed 's/%3D/=/g;s/%26/\&/g')

echo "Step 2: Accessing Landing Page and extracting prelogin link..." | tee -a "$LOG_FILE"
HTML=$(perform_curl -s "http://portal.iob.de")
# Extract the specific link target for 'Online gehen'
PRELOGIN_URL=$(echo "$HTML" | sed -n 's/.*href="\([^"]*\/prelogin\)".*/\1/p' | head -n 1)

echo "Step 3: Triggering prelogin via $PRELOGIN_URL..." | tee -a "$LOG_FILE"
perform_curl "$PRELOGIN_URL"

echo "Step 4: Executing Hotsplots authentication..." | tee -a "$LOG_FILE"
AUTH_URL="https://www.hotsplots.de/auth/login.php?$QUERY_STRING"
# Submit login POST request
RESPONSE=$(perform_curl -X POST -d "button=Login" "$AUTH_URL")
echo "Auth Response completed." | tee -a "$LOG_FILE"

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -m 15 -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)"
    exit 1
fi