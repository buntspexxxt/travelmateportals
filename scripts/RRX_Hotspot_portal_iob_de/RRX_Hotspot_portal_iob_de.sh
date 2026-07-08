#!/bin/bash
# SCRIPT_VERSION="1.6.0"
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
RESPONSE=$(perform_curl -I "http://neverssl.com")
REDIRECT_URL=$(echo "$RESPONSE" | grep -i "Location:" | sed 's/Location: //g' | sed 's/\r//g' | head -n 1 | tr -d '[:space:]')

if [ -z "$REDIRECT_URL" ]; then
  echo "Failed to find redirect URL. Manual check required." | tee -a "$LOG_FILE"
  exit 1
fi

LOGIN_URL=$(echo "$REDIRECT_URL" | sed -n 's/.*loginurl=\(https%3a%2f%2f[^&]*\).*/\1/p' | sed 's/%3a/:/g;s/%2f/\//g')

echo "Step 2: Fetching portal redirect to extract auth data..." | tee -a "$LOG_FILE"
# The portal provides the login URL in the query string of the redirect

echo "Step 3: Submitting Hotsplots credentials via login endpoint..." | tee -a "$LOG_FILE"
# Extracting parameters from the redirect URL found in Step 1
CHALLENGE=$(echo "$REDIRECT_URL" | sed -n 's/.*challenge=\([^&]*\).*/\1/p')
UAMIP=$(echo "$REDIRECT_URL" | sed -n 's/.*uamip=\([^&]*\).*/\1/p')
UAMPORT=$(echo "$REDIRECT_URL" | sed -n 's/.*uamport=\([^&]*\).*/\1/p')
MAC=$(echo "$REDIRECT_URL" | sed -n 's/.*mac=\([^&]*\).*/\1/p')

echo "Extracted Challenge: $CHALLENGE" | tee -a "$LOG_FILE"

# Hotsplots portals typically require these fields. Leaving username/password blank for open access.
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