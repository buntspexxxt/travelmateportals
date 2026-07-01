#!/bin/bash

LOG_FILE="/tmp/portal_login.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Starting Accor ibis captive portal login script..."

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

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/120.0.0.0"
COOKIES="/tmp/portal_cookies.txt"

echo "Accessing landing page to retrieve session tokens..."
# We use the root URL to trigger the portal logic
curl -A "$USER_AGENT" -v -L -c "$COOKIES" -b "$COOKIES" "https://accor.conn4.com/" > /tmp/portal_page.html 2>&1

# Modern Accor portals are Vue.js driven and often communicate via API calls to /sscp/
# We look for the base API path defined in __sceneConfig
SCENE_URI=$(grep -oE '"scenePlayerUri":"/[^/]+/[^/]+/' /tmp/portal_page.html | cut -d'"' -f4)
echo "Detected Scene Player URI: $SCENE_URI"

# The portal logic typically requires identifying the 'Free' plan via a POST request.
# We emulate a selection of the free plan. Based on Accor/Conn4 architecture, 
# the next step involves calling the scene player to initialize the 'Free 24h' connection.

echo "Requesting connection initialization via Scene API..."
# Mimicking the connection selection request
RESPONSE=$(curl -A "$USER_AGENT" -v -b "$COOKIES" -c "$COOKIES" -X POST "https://accor.conn4.com${SCENE_URI}select" -H "Content-Type: application/json" -d '{"planId": "free-24h"}')
echo "API Response: $RESPONSE"

# Verify internet connectivity
echo "Performing connectivity check..."
ping -c 3 8.8.8.8 >/dev/null && echo "Success: Internet reached." && exit 0 || echo "Error: Connection failed." && exit 1