#!/bin/bash
# SCRIPT_VERSION="1.4.0"
trap 'rm -f "${COOKIE_FILE:-}" "${LOG_FILE:-}"' EXIT
LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE=$(mktemp)
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Starting Hotsplots/RRX Portal Login Process..." | tee -a "$LOG_FILE"

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
# Extracting parameters from the redirect URL seen in previous attempts
REDIRECT_RESPONSE=$(perform_curl -I "http://neverssl.com")
LOGIN_URL=$(echo "$REDIRECT_RESPONSE" | grep -i "Location:" | sed 's/Location: //g' | sed 's/\r//g' | head -n 1 | tr -d '[:space:]')

if [[ ! "$LOGIN_URL" =~ "hotsplots.de" ]]; then
    echo "Error: Could not capture Hotsplots redirect URL. Using fallback." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Step 2: Fetching Hotsplots login page..." | tee -a "$LOG_FILE"
LOGIN_PAGE=$(perform_curl -L "$LOGIN_URL")

echo "Step 3: Extracting hidden form fields (challenge, etc)..." | tee -a "$LOG_FILE"
# Using POSIX sed to extract hidden inputs
CHALLENGE=$(echo "$LOGIN_PAGE" | sed -n 's/.*name="challenge" value="\([^"]*\)".*/\1/p')
UAMIP=$(echo "$LOGIN_PAGE" | sed -n 's/.*name="uamip" value="\([^"]*\)".*/\1/p')
UAMPORT=$(echo "$LOGIN_PAGE" | sed -n 's/.*name="uamport" value="\([^"]*\)".*/\1/p')
MAC=$(echo "$LOGIN_PAGE" | sed -n 's/.*name="mac" value="\([^"]*\)".*/\1/p')

POST_DATA="username=&password=&challenge=$CHALLENGE&uamip=$UAMIP&uamport=$UAMPORT&mac=$MAC&button=Login"

echo "Step 4: Submitting login request..." | tee -a "$LOG_FILE"
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