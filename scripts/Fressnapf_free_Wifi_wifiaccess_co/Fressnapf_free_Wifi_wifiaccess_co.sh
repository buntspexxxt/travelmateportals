#!/bin/bash
LOG_FILE="/tmp/portal_log.txt"
COOKIE_FILE="/tmp/portal_cookies.txt"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Waiting for DHCP..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

echo "Fetching redirect URL..." | tee -a "$LOG_FILE"
REDIRECT_URL=$(curl -A "$USER_AGENT" -c "$COOKIE_FILE" -L "http://connectivitycheck.gstatic.com/generate_204" -v 2>&1 | grep "Location:" | tail -n 1 | awk '{print $2}' | tr -d '\r')
BASE_URL=$(echo "$REDIRECT_URL" | cut -d'/' -f1-4)
echo "Detected Base URL: $BASE_URL" | tee -a "$LOG_FILE"

echo "Initializing session and fetching portal HTML..." | tee -a "$LOG_FILE"
HTML_CONTENT=$(curl -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -L "$BASE_URL/" -v 2>&1)

echo "Extracting API path..." | tee -a "$LOG_FILE"
API_URL="$BASE_URL/portal_api.php"

echo "Submitting 'init' request..." | tee -a "$LOG_FILE"
curl -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -d "action=init" "$API_URL" -v >> "$LOG_FILE" 2>&1

echo "Authenticating with blank credentials (Accept Terms)..." | tee -a "$LOG_FILE"
# Ucopia portals usually use the action 'authenticate'.
# Some configurations require policy_accept=true
RESPONSE=$(curl -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -d "action=authenticate&policy_accept=true&login=&password=&secure_pwd=" "$API_URL" -v 2>&1)

echo "Response: $RESPONSE" | tee -a "$LOG_FILE"

echo "Verifying internet connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Successfully connected!" && exit 0 || echo "Connection failed." && exit 1