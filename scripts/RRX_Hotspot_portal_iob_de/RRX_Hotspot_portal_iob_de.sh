#!/bin/bash
# SCRIPT_VERSION="1.3.0"
trap 'rm -f "${COOKIE_FILE:-}" "${LOG_FILE:-}"' EXIT
LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE=$(mktemp)
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Starting RRX Hotspot Login Process..." | tee -a "$LOG_FILE"

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

echo "Step 1: Capturing redirect URL from connectivity check..." | tee -a "$LOG_FILE"
REDIRECT_INFO=$(curl -k -v -I -A "$USER_AGENT" "http://neverssl.com" 2>&1)
REDIRECT_URL=$(echo "$REDIRECT_INFO" | sed -n 's/^[Ll]ocation: \(.*\)/\1/p' | sed 's/\r//g' | head -n 1)

# Extract base URL and Hotsplots parameters
LOGIN_URL_ENCODED=$(echo "$REDIRECT_URL" | sed -n 's/.*loginurl=\(.*\)/\1/p')
LOGIN_URL=$(echo -e "${LOGIN_URL_ENCODED//%/\\x}")

CHALLENGE=$(echo "$LOGIN_URL" | sed -n 's/.*challenge=\([^&]*\).*/\1/p')
UAMIP=$(echo "$LOGIN_URL" | sed -n 's/.*uamip=\([^&]*\).*/\1/p')
UAMPORT=$(echo "$LOGIN_URL" | sed -n 's/.*uamport=\([^&]*\).*/\1/p')
MAC=$(echo "$LOGIN_URL" | sed -n 's/.*mac=\([^&]*\).*/\1/p')
NASID=$(echo "$LOGIN_URL" | sed -n 's/.*nasid=\([^&]*\).*/\1/p')

# Hotsplots login page requires visiting prelogin then the auth page
echo "Step 2: Initializing CoovaChilli session..." | tee -a "$LOG_FILE"
perform_curl "http://$UAMIP:$UAMPORT/prelogin"

echo "Step 3: Submitting Hotsplots Auth..." | tee -a "$LOG_FILE"
# The 'button=Login' or 'accept=Accept' is usually required for CoovaChilli portals
POST_DATA="username=&password=&button=Login&challenge=$CHALLENGE&uamip=$UAMIP&uamport=$UAMPORT&mac=$MAC&nasid=$NASID"

# Perform login against the hotsplots auth URL
AUTH_HOST=$(echo "$LOGIN_URL" | cut -d'/' -f1-3)
AUTH_PATH=$(echo "$LOGIN_URL" | cut -d'/' -f4-)
perform_curl -X POST -d "$POST_DATA" "$AUTH_HOST/$AUTH_PATH"

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)"
    exit 1
fi