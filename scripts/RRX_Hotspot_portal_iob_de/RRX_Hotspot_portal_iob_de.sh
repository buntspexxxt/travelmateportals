#!/bin/bash
# SCRIPT_VERSION="1.2.0"
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

echo "Step 1: Fetching initial landing page and extract redirect target..." | tee -a "$LOG_FILE"
REDIRECT_URL=$(curl -k -L -w "%{url_effective}" -o /dev/null -A "$USER_AGENT" "http://neverssl.com")

echo "Step 2: Accessing /prelogin to negotiate Hotsplots session..." | tee -a "$LOG_FILE"
# The portal requires interaction with the Hotsplots redirect URL found in the initial landing redirect
LOGIN_URL=$(echo "$REDIRECT_URL" | sed -n 's/.*loginurl=\([^&]*\).*/\1/p' | tr -d '\015' | sed 's/%3a/:/g;s/%2f/\//g')

echo "Step 3: Submitting initial credentials/trigger to Hotsplots..." | tee -a "$LOG_FILE"
# Hotsplots login typically expects these params extracted from the URL query string
POST_DATA="username=&password=&button=Login&$(echo "$REDIRECT_URL" | grep -o '?.*' | cut -c 2-)"

RESPONSE=$(perform_curl -X POST -d "$POST_DATA" "$LOGIN_URL")
echo "HTTP Response Received." | tee -a "$LOG_FILE"

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    exit 1
fi