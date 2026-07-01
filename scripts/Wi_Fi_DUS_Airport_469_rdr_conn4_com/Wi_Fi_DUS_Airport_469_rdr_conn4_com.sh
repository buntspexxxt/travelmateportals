#!/bin/bash
LOG_FILE="/tmp/captive_portal.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Starting Conn4 captive portal script..."

# Wait for DHCP
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

echo "Fetching initial portal index..."
curl -v -A "$USER_AGENT" -c "$COOKIE_FILE" -o /tmp/index.html "https://469.rdr.conn4.com/"

# Extract WBS Token from the script block in HTML
echo "Extracting WBS Token from HTML..."
WBS_TOKEN=$(grep -o '"token":"[^"]*"' /tmp/index.html | head -1 | cut -d'"' -f4)
if [ -z "$WBS_TOKEN" ]; then
    echo "Failed to find WBS token. Exiting."
    exit 1
fi
echo "Token found: $WBS_TOKEN"

echo "Requesting session initialization..."
# Send the token to the roaming/return endpoint to finalize the session handshake
RESPONSE=$(curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -X POST "https://469.rdr.conn4.com/wbs/de/roaming/return/" -d "token=$WBS_TOKEN")
echo "HTTP Response: $RESPONSE"

echo "Performing final connectivity check..."
ping -c 3 8.8.8.8 >/dev/null && echo "Internet access confirmed." && exit 0 || exit 1