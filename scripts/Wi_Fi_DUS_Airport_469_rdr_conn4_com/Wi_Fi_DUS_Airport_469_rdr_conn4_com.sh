#!/bin/bash
LOG_FILE="/tmp/captive_portal.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Starting Conn4 captive portal multi-step automation..."

echo "Waiting for DHCP (IP & Gateway)..."
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful."
        sleep 6
        break
    fi
    sleep 1
done

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE="/tmp/cookies_captive_portal.txt"

echo "Step 1: Fetching initial index to initialize cookies..."
curl -v -A "$USER_AGENT" -c "$COOKIE_FILE" -o /tmp/index.html "https://469.rdr.conn4.com/"

echo "Step 2: Extracting WBS token from HTML dynamically..."
# Extract token using sed to find the json structure
WBS_TOKEN=$(grep -o '"token":"[^"]*"' /tmp/index.html | head -1 | sed 's/"token":"//;s/"//')

if [ -z "$WBS_TOKEN" ]; then
    echo "Failed to find WBS token in HTML. Exiting."
    exit 1
fi
echo "Token found: $WBS_TOKEN"

echo "Step 3: Sending authentication handshake..."
# The API endpoint is dynamically derived from the logic seen in the HTML/JS snippet provided
RESPONSE=$(curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -X POST "https://469.rdr.conn4.com/wbs/de/roaming/return/" -d "token=$WBS_TOKEN")

echo "HTTP Response: $RESPONSE"

echo "Step 4: Performing connectivity check..."
ping -c 3 8.8.8.8 >/dev/null && echo "Internet access confirmed." && exit 0 || exit 1