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

# Extract Scene URI
SCENE_URI=$(grep -oE '"scenePlayerUri":"/[^/]+/[^/]+/' /tmp/portal_page.html | cut -d'"' -f4)
echo "Detected Scene Player URI: $SCENE_URI"

echo "Requesting connection initialization via Scene API..."
RESPONSE=$(curl -A "$USER_AGENT" -v -b "$COOKIES" -c "$COOKIES" -X POST "https://accor.conn4.com${SCENE_URI}select" -H "Content-Type: application/json" -d '{"planId": "free-24h"}')
echo "API Response: $RESPONSE"

echo "Confirming connection..."
CONN_RESPONSE=$(curl -A "$USER_AGENT" -v -b "$COOKIES" -c "$COOKIES" -X POST "https://accor.conn4.com${SCENE_URI}connect" -H "Content-Type: application/json" -d '{}')
echo "Connection Status: $CONN_RESPONSE"

echo "Checking for secondary acceptance requirement..."
# Check if terms need an explicit accept POST
ACCEPT_RESPONSE=$(curl -A "$USER_AGENT" -v -b "$COOKIES" -c "$COOKIES" -X POST "https://accor.conn4.com${SCENE_URI}accept" -H "Content-Type: application/json" -d '{"terms": true}')
echo "Acceptance Response: $ACCEPT_RESPONSE"

echo "Performing connectivity check..."
ping -c 3 8.8.8.8 >/dev/null && echo "Success: Internet reached." && exit 0 || echo "Error: Connection failed." && exit 1