#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
echo "Starting Login Sequence..." | tee -a "$LOG_FILE"

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

echo "Fetching landing page to get session..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -v -A "$USER_AGENT" -c /tmp/c.txt -b /tmp/c.txt "https://service.thecloud.eu/service-platform/home")
echo "HTTP Response: $?" | tee -a "$LOG_FILE"

echo "Extracting the 'Get Online' URL..." | tee -a "$LOG_FILE"
GET_ONLINE_URL=$(echo "$RESPONSE" | grep -o 'href="https://service.thecloud.eu/service-platform/url/[0-9]*"' | head -1 | cut -d'"' -f2)

if [ -z "$GET_ONLINE_URL" ]; then
    echo "Failed to find login URL. Exiting." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Navigating to: $GET_ONLINE_URL" | tee -a "$LOG_FILE"
curl -v -A "$USER_AGENT" -c /tmp/c.txt -b /tmp/c.txt "$GET_ONLINE_URL" | tee -a "$LOG_FILE"

echo "Performing connectivity check..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Success: Internet reachable." | tee -a "$LOG_FILE" && exit 0 || exit 1