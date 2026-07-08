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

echo "Step 1: Extracting auth redirect URL from landing page..." | tee -a "$LOG_FILE"
LANDING_RESPONSE=$(perform_curl -L "http://portal.iob.de/")

echo "Step 2: Following redirect to prelogin..." | tee -a "$LOG_FILE"
# The HTML indicates clicking 'Online gehen' redirects to 192.168.44.1/prelogin
AUTH_PAGE=$(perform_curl -L "http://192.168.44.1/prelogin")

echo "Step 3: Parsing parameters from the actual Hotsplots login page..." | tee -a "$LOG_FILE"
# The previous log confirms the Hotsplots URL contains all necessary challenge data
# We extract the URL from the Location header of the prelogin response
REDIRECT_URL=$(echo "$AUTH_PAGE" | grep -i "Location:" | sed 's/Location: //g' | sed 's/\r//g' | head -n 1 | tr -d '[:space:]')

# Fallback if redirect header is not captured: use the pattern observed in previous logs
if [ -z "$REDIRECT_URL" ]; then
    echo "Searching for Hotsplots login form..." | tee -a "$LOG_FILE"
    # We need the full URL from the browser's redirect perspective
    REDIRECT_URL="https://www.hotsplots.de/auth/login.php"
fi

echo "Step 4: Submitting Hotsplots credentials..." | tee -a "$LOG_FILE"
# Based on Hotsplots standard: extract variables from the URL or the current page form
# We assume empty fields for terms-of-service acceptance
POST_DATA="button=Login&username=&password="

echo "Executing Final POST to Hotsplots..." | tee -a "$LOG_FILE"
perform_curl -X POST -d "$POST_DATA" "$REDIRECT_URL"

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)"
    exit 1
fi