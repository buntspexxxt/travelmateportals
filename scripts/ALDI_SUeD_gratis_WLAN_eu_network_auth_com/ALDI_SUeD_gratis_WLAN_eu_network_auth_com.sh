#!/bin/bash

LOG_FILE="/tmp/wifi_login.log"
COOKIE_FILE="/tmp/wifi_cookies.txt"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Starting ALDI WLAN login process..." | tee -a "$LOG_FILE"

# 1. Wait for network
echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

# 2. Get initial challenge
echo "Fetching captive portal landing page..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -v -A "$USER_AGENT" -c "$COOKIE_FILE" -L "http://detectportal.firefox.com/success.txt" 2>&1)

# Extract base URL and Query Params
REDIRECT_URL=$(echo "$RESPONSE" | grep -i "Location:" | tail -n 1 | sed -n 's/.*Location: //p' | tr -d '\r')
if [ -z "$REDIRECT_URL" ]; then
    echo "Failed to find redirect URL." | tee -a "$LOG_FILE"
    exit 1
fi

BASE_URL=$(echo "$REDIRECT_URL" | cut -d'?' -f1)
QUERY_PARAMS=$(echo "$REDIRECT_URL" | cut -d'?' -f2)

# 3. Handle 'Grant' logic as requested by HTML
echo "Executing AJAX-style grant request..." | tee -a "$LOG_FILE"
# The HTML uses a HEAD request to extract the 'Continue-Url' header, then redirects.
echo "Fetching Continue-Url via HEAD..." | tee -a "$LOG_FILE"
CONTINUE_HEADER=$(curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -I -X HEAD "$BASE_URL?$QUERY_PARAMS" 2>&1 | grep -i "Continue-Url:" | awk '{print $2}' | tr -d '\r')

if [ -z "$CONTINUE_HEADER" ]; then
    echo "Could not extract Continue-Url. Trying to access /grant directly." | tee -a "$LOG_FILE"
    GRANT_URL="${BASE_URL%/*}/grant"
else
    GRANT_URL="${BASE_URL%/*}/grant?continue_url=$CONTINUE_HEADER"
fi

echo "Submitting final grant to $GRANT_URL" | tee -a "$LOG_FILE"
curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" "$GRANT_URL" 2>&1 | tee -a "$LOG_FILE"

# 4. Final check
echo "Running connectivity check..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Success: Internet access confirmed." | tee -a "$LOG_FILE" && exit 0 || exit 1