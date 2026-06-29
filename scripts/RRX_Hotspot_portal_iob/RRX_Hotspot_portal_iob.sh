#!/bin/bash

LOG_FILE="/tmp/wifi_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

echo "Detecting captive portal redirect..." | tee -a "$LOG_FILE"
REDIRECT_URL=$(curl -v -A "$USER_AGENT" http://neverssl.com 2>&1 | grep -i "Location:" | sed -n "s/.*Location: //p" | tr -d '\\r')
echo "Redirect URL found: $REDIRECT_URL" | tee -a "$LOG_FILE"

# The logs show a CoovaChilli/Hotsplots portal structure
# We need to extract parameters from the redirect URL to authenticate against the UAM server

UAM_BASE="https://www.hotsplots.de/auth/login.php"
QUERY=$(echo "$REDIRECT_URL" | grep -o '?.*')

# Construct the login POST request based on the discovered redirect parameters
echo "Proceeding to login via Hotsplots gateway..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -v -A "$USER_AGENT" -L "$UAM_BASE$QUERY&username=&password=" 2>&1)

echo "HTTP Response: $RESPONSE" | tee -a "$LOG_FILE"

echo "Performing final connectivity check..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Success: Internet access confirmed." || { echo "Error: Connection failed."; exit 1; }
exit 0