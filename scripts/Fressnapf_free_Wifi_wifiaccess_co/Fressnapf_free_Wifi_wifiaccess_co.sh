#!/bin/bash

LOG_FILE="/tmp/wifi_login.log"
echo "Starting Portal Login Script..." | tee -a "$LOG_FILE"

# Smart wait loop
echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE="/tmp/c.txt"

echo "Fetching initial landing page to initialize session..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -m 15 -v -A "$USER_AGENT" -c "$COOKIE_FILE" "https://wifiaccess.co/103/portal/" 2>&1)
echo "Initial Request Result: $RESPONSE" | tee -a "$LOG_FILE"

# The portal logic uses AJAX calls to portal_api.php. 
# First we must initialize the API as seen in main.js/portal.js
CONTROLLER_HOST="wifiaccess.co"

echo "Initializing API..." | tee -a "$LOG_FILE"
API_INIT=$(curl -m 15 -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -d "action=init" "https://$CONTROLLER_HOST/portal_api.php" 2>&1)
echo "API Init Response: $API_INIT" | tee -a "$LOG_FILE"

# Simulate clicking 'Connect' (often requires no user/pass for open portals)
echo "Attempting connection (empty credentials for free access)..." | tee -a "$LOG_FILE"
# Most Ucopia portals with 'Connect' buttons expect authentication action
AUTH_RESPONSE=$(curl -m 15 -v -A "$USER_AGENT" -b "$COOKIE_FILE" -d "action=authenticate&login=&password=&policy_accept=1" "https://$CONTROLLER_HOST/portal_api.php" 2>&1)
echo "Auth Result: $AUTH_RESPONSE" | tee -a "$LOG_FILE"

# Final Connectivity Check
echo "Performing connectivity check..." | tee -a "$LOG_FILE"
if ping -c 3 8.8.8.8 >/dev/null; then
    echo "Successfully connected to internet." | tee -a "$LOG_FILE"
    exit 0
else
    echo "Connectivity check failed." | tee -a "$LOG_FILE"
    exit 1
fi