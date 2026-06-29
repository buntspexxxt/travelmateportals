#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
echo "Starting ALDI WiFi Login script" | tee -a "$LOG_FILE"

# Wait for DHCP
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

echo "Fetching redirect URL from captive portal..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -v -A "$USER_AGENT" -L http://detectportal.firefox.com/success.txt 2>&1)
LANDING_URL=$(echo "$RESPONSE" | grep -i "< Location:" | sed -n 's/.*Location: //p' | tr -d '\r')

if [ -z "$LANDING_URL" ]; then
    echo "Failed to find landing URL. Portal might already be logged in." | tee -a "$LOG_FILE"
    exit 0
fi

echo "Landing URL: $LANDING_URL" | tee -a "$LOG_FILE"
BASE_URL=$(echo "$LANDING_URL" | cut -d'?' -f1)
QUERY_STRING=$(echo "$LANDING_URL" | grep -o '?.*' | cut -c 2-)

echo "Submitting 'grant' request..." | tee -a "$LOG_FILE"
GRANT_URL="${BASE_URL}grant?${QUERY_STRING}"

curl -v -A "$USER_AGENT" -X HEAD -H "X-Requested-With: XMLHttpRequest" "$GRANT_URL" > /dev/null 2>&1

echo "Performing final connectivity check..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "Success: Internet connected." | tee -a "$LOG_FILE"
    exit 0
else
    echo "Error: Internet not reachable." | tee -a "$LOG_FILE"
    exit 1
fi