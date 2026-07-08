#!/bin/bash
# SCRIPT_VERSION="1.0.0"
trap 'rm -f "${COOKIE_FILE:-}" "${LOG_FILE:-}"' EXIT
LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE=$(mktemp)
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Starting RRX Hotspot Portal Login Process..." | tee -a "$LOG_FILE"

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
# Extracting Hotsplots login URL from the portal redirect
RESPONSE=$(perform_curl -I "http://neverssl.com")
LOGIN_URL=$(echo "$RESPONSE" | sed -n 's/^Location: \(.*\)/\1/p' | sed 's/\r//g' | head -n 1 | tr -d '[:space:]')

# The RRX portal redirects to portal.iob.de which contains the hotsplots URL in the loginurl parameter
# We need to extract this parameter and follow it
REAL_LOGIN_URL=$(echo "$LOGIN_URL" | sed -n 's/.*loginurl=\(.*\)/\1/p' | sed 's/%3a/:/g;s/%2f/\//g;s/%26/\&/g;s/%3d/=/g;s/%253a/:/g;s/%253d/=/g;s/%252f/\//g')

echo "Step 2: Accessing RRX Landing Page..." | tee -a "$LOG_FILE"
# First, acknowledge the local landing page
perform_curl "http://192.168.44.1/prelogin"

echo "Step 3: Fetching actual Hotsplots authentication page..." | tee -a "$LOG_FILE"
LOGIN_PAGE=$(perform_curl "$REAL_LOGIN_URL")

echo "Step 4: Extracting hidden form fields (challenge, etc)..." | tee -a "$LOG_FILE"
CHALLENGE=$(echo "$LOGIN_PAGE" | sed -n 's/.*name="challenge" value="\([^"]*\)".*/\1/p')
UAMIP=$(echo "$LOGIN_PAGE" | sed -n 's/.*name="uamip" value="\([^"]*\)".*/\1/p')
UAMPORT=$(echo "$LOGIN_PAGE" | sed -n 's/.*name="uamport" value="\([^"]*\)".*/\1/p')
MAC=$(echo "$LOGIN_PAGE" | sed -n 's/.*name="mac" value="\([^"]*\)".*/\1/p')

POST_DATA="username=&password=&challenge=$CHALLENGE&uamip=$UAMIP&uamport=$UAMPORT&mac=$MAC&button=Login"

echo "Step 5: Submitting Hotsplots login request..." | tee -a "$LOG_FILE"
perform_curl -X POST -d "$POST_DATA" "$REAL_LOGIN_URL"

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)"
    exit 1
fi