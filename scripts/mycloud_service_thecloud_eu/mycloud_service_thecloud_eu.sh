#!/bin/bash

LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE="/tmp/portal_cookies.txt"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

echo "Fetching initial landing page to obtain session cookies..." | tee -a "$LOG_FILE"
curl -v -A "$UA" -c "$COOKIE_FILE" -L "https://service.thecloud.eu/service-platform/home" > /dev/null 2>&1

echo "Extracting the 'Get Online' link from the HTML..." | tee -a "$LOG_FILE"
GET_ONLINE_URL=$(curl -v -A "$UA" -b "$COOKIE_FILE" -L "https://service.thecloud.eu/service-platform/home" 2>&1 | grep -o 'href="https://service.thecloud.eu/service-platform/url/[0-9]*"' | head -1 | sed 's/href="//' | sed 's/"//')

if [ -z "$GET_ONLINE_URL" ]; then
    echo "Could not find 'Get Online' URL. Searching for existing session..." | tee -a "$LOG_FILE"
else
    echo "Found URL: $GET_ONLINE_URL" | tee -a "$LOG_FILE"
    echo "Navigating to activation URL..." | tee -a "$LOG_FILE"
    RESPONSE=$(curl -v -A "$UA" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -L -o /dev/null -w "%{http_code}" "$GET_ONLINE_URL")
    echo "HTTP Response from navigation: $RESPONSE" | tee -a "$LOG_FILE"
fi

echo "Performing final WiFi4EU registration/handshake..." | tee -a "$LOG_FILE"
# The portal requires the JS tracking link to mark the session as active
curl -v -A "$UA" -b "$COOKIE_FILE" "https://collection.wifi4eu.ec.europa.eu/wifi4eu.min.js" > /dev/null 2>&1

echo "Checking internet connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 > /dev/null && echo "Login successful and internet is reachable." | tee -a "$LOG_FILE" || { echo "Login failed or no internet." | tee -a "$LOG_FILE"; exit 1; }