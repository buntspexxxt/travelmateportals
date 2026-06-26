#!/bin/bash
LOG_FILE="/tmp/wifi_login.log"
echo "Starting login script..." | tee -a "$LOG_FILE"

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

echo "Fetching initial portal redirect..." | tee -a "$LOG_FILE"
# Fetch to get the initial redirect URL
REDIRECT_RESPONSE=$(curl -v -L -A "$USER_AGENT" -o /dev/null -w "%{url_effective}" http://detectportal.firefox.com/success.txt 2>&1)
LANDING_URL=$(echo "$REDIRECT_RESPONSE" | grep "Location:" | tail -n1 | awk '{print $2}' | tr -d '\r')

if [ -z "$LANDING_URL" ]; then
    echo "Failed to extract landing URL!" | tee -a "$LOG_FILE"
    exit 1
fi

echo "Landing URL: $LANDING_URL" | tee -a "$LOG_FILE"

# Extract base URL
BASE_URL=$(echo "$LANDING_URL" | cut -d'?' -f1)
echo "Base URL: $BASE_URL" | tee -a "$LOG_FILE"

echo "Performing XHR handshake to get Continue-Url..." | tee -a "$LOG_FILE"
# The portal requires an XHR HEAD request to retrieve the 'Continue-Url' header
CONTINUE_URL=$(curl -v -I -A "$USER_AGENT" -H "X-Requested-With: XMLHttpRequest" "$LANDING_URL" 2>&1 | grep -i "Continue-Url:" | awk '{print $2}' | tr -d '\r')

if [ -z "$CONTINUE_URL" ]; then
    echo "Failed to extract Continue-Url from headers!" | tee -a "$LOG_FILE"
    exit 1
fi

echo "Continue URL: $CONTINUE_URL" | tee -a "$LOG_FILE"

# Formulate the grant URL
GRANT_URL="${BASE_URL}grant?continue_url=$(echo -n "$CONTINUE_URL" | python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read()))")"
echo "Submitting grant request: $GRANT_URL" | tee -a "$LOG_FILE"

RESPONSE=$(curl -v -L -A "$USER_AGENT" "$GRANT_URL" 2>&1)
echo "HTTP Response: $RESPONSE" | tee -a "$LOG_FILE"

echo "Connectivity check..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Success: Internet connected." | tee -a "$LOG_FILE" && exit 0 || exit 1