#!/bin/bash
# SCRIPT_VERSION="1.2.0"
trap 'rm -f "${COOKIE_FILE:-}"' EXIT
LOG_FILE="/tmp/portal_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE=$(mktemp)

echo "Starting Peplink Portal Login sequence" | tee -a "$LOG_FILE"

echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network ready." | tee -a "$LOG_FILE"
        break
    fi
    sleep 2
done

echo "Fetching redirect URL..." | tee -a "$LOG_FILE"
REDIRECT_URL=$(curl -k -v -A "$USER_AGENT" -o /dev/null -w "%{redirect_url}" "http://connectivitycheck.gstatic.com/generate_204" | sed "s/\r//g")
BASE_URL=$(echo "$REDIRECT_URL" | cut -d'/' -f1-3)
QUERY_STRING=$(echo "$REDIRECT_URL" | sed -n "s/.*\?//p")

echo "Checking session status..." | tee -a "$LOG_FILE"
SESSION_RESPONSE=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "https://guest7.ic.peplink.com/cp/session/resume?$QUERY_STRING")
echo "Session API Response: $SESSION_RESPONSE" | tee -a "$LOG_FILE"

# Extracting parameters dynamically from the JS-like logic observed in HTML
SN=$(echo "$SESSION_RESPONSE" | sed -n 's/.*"sn":"\([^"]*\)".*/\1/p')
CP_ID=$(echo "$SESSION_RESPONSE" | sed -n 's/.*"cp_id":"\([^"]*\)".*/\1/p')
CHECKSUM=$(echo "$SESSION_RESPONSE" | sed -n 's/.*"checksum":"\([^"]*\)".*/\1/p')

echo "Submitting login request to Peplink portal..." | tee -a "$LOG_FILE"
LOGIN_PARAMS="resume=true&command=login&sn=$SN&cp_id=$CP_ID&checksum=$CHECKSUM&lang=en&_=$(date +%s)"
curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "https://guest7.ic.peplink.com/cp/login?$LOGIN_PARAMS" | tee -a "$LOG_FILE"

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: No internet connectivity (Code: $CHECK_CODE)"
    exit 1
fi