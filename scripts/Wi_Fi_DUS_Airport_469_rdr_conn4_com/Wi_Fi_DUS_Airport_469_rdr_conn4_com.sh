#!/bin/bash

LOG_FILE="/tmp/portal_login.log"
echo "Starting portal login script..." | tee -a "$LOG_FILE"

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
COOKIE_FILE="/tmp/portal_cookies.txt"
BASE_URL="https://469.rdr.conn4.com"

echo "Fetching initial portal page..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -v -A "$USER_AGENT" -c "$COOKIE_FILE" "$BASE_URL/" 2>&1)
echo "HTTP Response Received." | tee -a "$LOG_FILE"

echo "Extracting WBS Token from HTML..." | tee -a "$LOG_FILE"
# Extracting the JSON token object from the script block in the HTML
WBS_TOKEN=$(grep -o 'conn4.hotspot.wbsToken = {[^{]*"token":"[^"]*"' /tmp/portal_tmp_1782465966/portal/index.html | sed 's/.*"token":"//' | sed 's/".*//')

if [ -z "$WBS_TOKEN" ]; then
    echo "Failed to extract WBS Token. Check logs." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Submitting token to portal..." | tee -a "$LOG_FILE"
# The portal logic indicates this is a token-based handshake. POSTing to verify/login.
POST_DATA="token=$WBS_TOKEN"
RESULT=$(curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -d "$POST_DATA" "$BASE_URL/wbs/de/roaming/return/" 2>&1)
echo "Final request result: $RESULT" | tee -a "$LOG_FILE"

echo "Performing connectivity check..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Connectivity confirmed!" | tee -a "$LOG_FILE" && exit 0 || exit 1