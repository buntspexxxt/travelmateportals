#!/bin/bash
# SCRIPT_VERSION="1.5.0"
trap 'rm -f "${COOKIE_FILE:-}" "${LOG_FILE:-}"' EXIT
LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE=$(mktemp)
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Starting RRX Hotspot Portal Login Process..." | tee -a "$LOG_FILE"

# Network Wait
echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
done

perform_curl() {
    curl -k -v -L -A "$USER_AGENT" -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$@"
}

echo "Step 1: Identifying redirect parameters..." | tee -a "$LOG_FILE"
# Fetch the portal landing page to catch the Hotsplots redirect URL in the query string
RESPONSE=$(perform_curl -I "http://neverssl.com")
REDIRECT_URL=$(echo "$RESPONSE" | grep -i "Location:" | sed 's/Location: //g' | sed 's/\r//g' | head -n 1 | tr -d '[:space:]')

echo "Captured Redirect URL: $REDIRECT_URL" | tee -a "$LOG_FILE"

# Extract base login URL from the redirect query param
LOGIN_URL=$(echo "$REDIRECT_URL" | sed -n 's/.*loginurl=\(https%3a%2f%2f[^&]*\).*/\1/p' | sed 's/%3a/:/g;s/%2f/\//g')

echo "Step 2: Fetching intermediate RRX landing page..." | tee -a "$LOG_FILE"
# The portal first hits portal.iob.de which contains the 'Online gehen' link
perform_curl "http://portal.iob.de"

echo "Step 3: Following prelogin trigger..." | tee -a "$LOG_FILE"
# Clicking 'Online gehen' points to the local 192.168.44.1 prelogin
perform_curl "http://192.168.44.1/prelogin"

echo "Step 4: Submitting final Hotsplots credentials..." | tee -a "$LOG_FILE"
# Now submit to the actual hotsplots auth URL extracted earlier
# Extracting parameters dynamically for the POST request
CHALLENGE=$(echo "$LOGIN_URL" | sed -n 's/.*challenge=\([^&]*\).*/\1/p')
UAMIP=$(echo "$LOGIN_URL" | sed -n 's/.*uamip=\([^&]*\).*/\1/p')
UAMPORT=$(echo "$LOGIN_URL" | sed -n 's/.*uamport=\([^&]*\).*/\1/p')
MAC=$(echo "$LOGIN_URL" | sed -n 's/.*mac=\([^&]*\).*/\1/p')

POST_DATA="username=&password=&challenge=$CHALLENGE&uamip=$UAMIP&uamport=$UAMPORT&mac=$MAC&button=Login"
perform_curl -X POST -d "$POST_DATA" "$LOGIN_URL"

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)"
    exit 1
fi