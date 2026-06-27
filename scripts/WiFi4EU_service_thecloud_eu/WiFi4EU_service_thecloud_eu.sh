#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
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
COOKIE_FILE="/tmp/cookies.txt"

echo "Fetching initial portal page to get cookies..." | tee -a "$LOG_FILE"
curl -v -A "$USER_AGENT" -c "$COOKIE_FILE" "https://service.thecloud.eu/service-platform/" > /tmp/portal_init.html 2>&1
echo "HTTP Response captured." | tee -a "$LOG_FILE"

echo "Extracting 'Get Online' link..." | tee -a "$LOG_FILE"
# Extract the specific URL from the 'Get Online' anchor tag found in the analysis
GET_ONLINE_URL=$(grep -o 'href="https://service.thecloud.eu/service-platform/url/[0-9]*"' /tmp/portal_init.html | head -1 | cut -d'"' -f2)

if [ -z "$GET_ONLINE_URL" ]; then
    echo "Failed to extract GET_ONLINE_URL. Check HTML parsing." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Navigating to: $GET_ONLINE_URL" | tee -a "$LOG_FILE"
RESPONSE=$(curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -L -o /dev/null -w "%{http_code}" "$GET_ONLINE_URL")

echo "HTTP Response: $RESPONSE" | tee -a "$LOG_FILE"

if [ "$RESPONSE" -eq 200 ]; then
    echo "Login request successful." | tee -a "$LOG_FILE"
else
    echo "Login failed with code $RESPONSE" | tee -a "$LOG_FILE"
    exit 1
fi

echo "Running connectivity check..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Connected to internet!" && exit 0 || exit 1