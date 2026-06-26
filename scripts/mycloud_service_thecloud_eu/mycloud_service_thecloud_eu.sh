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

echo "Fetching landing page..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -v -A "$USER_AGENT" -c /tmp/c.txt -b /tmp/c.txt "https://service.thecloud.eu/service-platform/home")

echo "Extracting initial login link..." | tee -a "$LOG_FILE"
GET_ONLINE_URL=$(echo "$RESPONSE" | grep -o 'https://service.thecloud.eu/service-platform/url/[0-9]*' | head -1)

if [ -z "$GET_ONLINE_URL" ]; then
    echo "Failed to find initial login URL. Exiting." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Submitting 'Get Online' request..." | tee -a "$LOG_FILE"
STEP1_RESPONSE=$(curl -v -L -A "$USER_AGENT" -c /tmp/c.txt -b /tmp/c.txt "$GET_ONLINE_URL")
echo "HTTP Response: $?" | tee -a "$LOG_FILE"

echo "Handling potential secondary consent/modal page..." | tee -a "$LOG_FILE"
# The portal often requires one more interaction to trigger the session activation
FINAL_TRIGGER=$(echo "$STEP1_RESPONSE" | grep -o 'https://service.thecloud.eu/service-platform/url/[0-9]*' | tail -1)

if [ -n "$FINAL_TRIGGER" ]; then
    echo "Found activation trigger: $FINAL_TRIGGER" | tee -a "$LOG_FILE"
    curl -v -L -A "$USER_AGENT" -c /tmp/c.txt -b /tmp/c.txt "$FINAL_TRIGGER"
fi

echo "Finalizing with drift_time (anti-bot check)..." | tee -a "$LOG_FILE"
curl -v -A "$USER_AGENT" -c /tmp/c.txt -b /tmp/c.txt "https://service.thecloud.eu/service-platform/drift_time_204"

echo "Performing final connectivity check..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Success: Internet reachable." | tee -a "$LOG_FILE" && exit 0 || exit 1