#!/bin/bash
LOG_FILE="/tmp/captive_portal.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Starting captive portal script for DUS Airport..."

# Wait for DHCP
for i in {1..20}; do
    if ip route | grep -q default; then echo "Gateway found."; sleep 6; break; fi
    sleep 1
done

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE="/tmp/cookies_captive_portal.txt"

echo "Fetching initial page..."
curl -v -A "$USER_AGENT" -c "$COOKIE_FILE" -L -o /tmp/page1.html "https://469.rdr.conn4.com/"

# Extract base64 token
WBS_TOKEN=$(grep -o '"token":"[^"]*"' /tmp/page1.html | cut -d'"' -f4)
echo "Token found: $WBS_TOKEN"

echo "Submitting initial session..."
RESPONSE=$(curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -X POST "https://469.rdr.conn4.com/wbs/de/roaming/return/" -d "token=$WBS_TOKEN")

# Based on the requirement: Select 'Free' and 'Accept'.
# Usually requires a POST to the 'grant' URL or a dynamic form submission.
echo "Checking for grant URL in JavaScript..."
GRANT_URL=$(grep -o 'https://[^"]*grant[^"]*' /tmp/page1.html | head -1)

if [ ! -z "$GRANT_URL" ]; then
    echo "Found Grant URL: $GRANT_URL. Proceeding to accept terms..."
    # Simulate clicking 'Free' and 'Accept'
    # Often portal uses a hidden form or a JSON trigger. We POST an 'accept' request.
    curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -X POST "$GRANT_URL" -d "accept=true&terms=accepted"
else
    echo "Warning: Could not identify explicit Grant URL. Attempting default bypass logic..."
fi

# Final connectivity check
echo "Performing connectivity check..."
ping -c 3 8.8.8.8 >/dev/null && echo "Success!" && exit 0 || exit 1