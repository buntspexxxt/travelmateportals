#!/bin/bash
LOG_FILE="/tmp/wifi_login.log"
echo "Starting multi-stage login script..." | tee -a "$LOG_FILE"

echo "Waiting for DHCP..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then echo "Gateway found." | tee -a "$LOG_FILE"; break; fi
    sleep 1
done

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE="/tmp/portal_cookies.txt"

echo "Stage 1: Fetching initial redirect" | tee -a "$LOG_FILE"
REDIRECT_URL=$(curl -v -L -A "$USER_AGENT" -c "$COOKIE_FILE" -o /dev/null -w "%{url_effective}" http://detectportal.firefox.com/success.txt 2>&1 | grep "Location:" | tail -n1 | awk '{print $2}' | tr -d '\r')
echo "Initial URL: $REDIRECT_URL" | tee -a "$LOG_FILE"

echo "Stage 2: Fetching portal page and extracting Continue-Url" | tee -a "$LOG_FILE"
# The portal HTML indicates an XHR request to the root path retrieves the Continue-Url header
BASE_PATH=$(echo "$REDIRECT_URL" | cut -d'?' -f1)
CONTINUE_URL=$(curl -v -I -A "$USER_AGENT" -b "$COOKIE_FILE" -H "X-Requested-With: XMLHttpRequest" "$BASE_PATH" 2>&1 | grep -i "Continue-Url:" | awk '{print $2}' | tr -d '\r')

if [ -z "$CONTINUE_URL" ]; then
    echo "Failed to find Continue-Url" | tee -a "$LOG_FILE"
    exit 1
fi
echo "Extracted Continue-Url: $CONTINUE_URL" | tee -a "$LOG_FILE"

echo "Stage 3: Submitting grant request" | tee -a "$LOG_FILE"
# Based on the JS logic in the provided HTML, we must hit the 'grant' endpoint with the header-extracted URL
GRANT_URL="${BASE_PATH}grant?continue_url=$(echo -n "$CONTINUE_URL" | python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read()))")"
echo "Requesting: $GRANT_URL" | tee -a "$LOG_FILE"

RESPONSE=$(curl -v -L -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$GRANT_URL" 2>&1)
echo "Response: $RESPONSE" | tee -a "$LOG_FILE"

echo "Connectivity check..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Success: Connected." | tee -a "$LOG_FILE" && exit 0 || exit 1