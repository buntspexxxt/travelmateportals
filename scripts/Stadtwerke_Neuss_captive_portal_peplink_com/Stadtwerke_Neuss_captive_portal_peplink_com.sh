#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
echo "Starting login script..." > "$LOG_FILE"

echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Fetching initial redirect to extract parameters..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -v -A "$USER_AGENT" -L http://neverssl.com 2>&1)
REDIRECT_URL=$(echo "$RESPONSE" | grep -oP 'Location: \Khttps://[^ ]+')

if [ -z "$REDIRECT_URL" ]; then
    echo "Failed to find redirect URL. Manual check required." | tee -a "$LOG_FILE"
    exit 1
fi

QUERY_STRING=$(echo "$REDIRECT_URL" | cut -d'?' -f2)
echo "Extracted Query String: $QUERY_STRING" | tee -a "$LOG_FILE"

echo "Attempting to resume session via Peplink API..." | tee -a "$LOG_FILE"
API_URL="https://guest7.ic.peplink.com/cp/session/resume?$QUERY_STRING"
RESUME_RESPONSE=$(curl -v -A "$USER_AGENT" -c /tmp/cookies.txt -b /tmp/cookies.txt "$API_URL")
echo "API Response: $RESUME_RESPONSE" | tee -a "$LOG_FILE"

# Perform the final login command if not already resumed
echo "Executing login command..." | tee -a "$LOG_FILE"
LOGIN_URL="https://guest7.ic.peplink.com/cp/login?$QUERY_STRING&command=login"
curl -v -A "$USER_AGENT" -c /tmp/cookies.txt -b /tmp/cookies.txt "$LOGIN_URL" | tee -a "$LOG_FILE"

echo "Verifying connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Success: Internet access confirmed." | tee -a "$LOG_FILE" && exit 0 || { echo "Failed: No internet." | tee -a "$LOG_FILE"; exit 1; }