#!/bin/bash

# Auto-injected cleanup trap for temporary session files
trap 'rm -f "${COOKIE_JAR:-}" "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
# SCRIPT_VERSION="1.0.0"

LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE=$(mktemp)
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
done

echo "Initial check for redirect..." | tee -a "$LOG_FILE"
REDIRECT_INFO=$(curl -k -v -A "$UA" -c "$COOKIE_FILE" -L "http://neverssl.com" 2>&1)

echo "Extracting Grant URL..." | tee -a "$LOG_FILE"
# Extracting the grant URL from the HTML hidden wbsToken json object found in the portal index
HTML=$(curl -k -A "$UA" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -L "https://canda-de.conn4.com")
GRANT_URL=$(echo "$HTML" | sed -n 's/.*"grant_url":"\([^"]*\)".*/\1/p' | sed 's/\\\//\//g')

if [ -z "$GRANT_URL" ]; then
    echo "Failed to find grant URL!" | tee -a "$LOG_FILE"
    exit 1
fi

echo "Submitting grant request to: $GRANT_URL" | tee -a "$LOG_FILE"
RESPONSE=$(curl -k -v -A "$UA" -b "$COOKIE_FILE" -X POST "$GRANT_URL" 2>&1)
echo "HTTP Response captured." | tee -a "$LOG_FILE"

echo "Verifying real Internet connectivity..." | tee -a "$LOG_FILE"
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    exit 1
fi