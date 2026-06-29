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

echo "Fetching initial landing page..." | tee -a "$LOG_FILE"
# Get initial page to establish session cookie
curl -v -A "$UA" -c "$COOKIE_FILE" -L "https://service.thecloud.eu/service-platform/home" >> "$LOG_FILE" 2>&1

echo "Fetching 'Get Online' portal link..." | tee -a "$LOG_FILE"
# The HTML shows a link to '/service-platform/url/20347' with the text 'Get Online'
# We extract the location of this link from the current page content
PORTAL_URL=$(curl -s -A "$UA" -b "$COOKIE_FILE" -L "https://service.thecloud.eu/service-platform/home" | grep -o 'href="[^"]*"' | grep 'url/20347' | cut -d'"' -f2)

if [ -z "$PORTAL_URL" ]; then
    echo "Could not find 'Get Online' URL. Attempting default path." | tee -a "$LOG_FILE"
    PORTAL_URL="https://service.thecloud.eu/service-platform/url/20347"
fi

echo "Navigating to portal URL: $PORTAL_URL" | tee -a "$LOG_FILE"
# Following the redirect chain to the actual login/registration
curl -v -A "$UA" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -L "$PORTAL_URL" >> "$LOG_FILE" 2>&1

echo "Submitting final authentication request..." | tee -a "$LOG_FILE"
# The registration endpoint found in the previous stage is the next logical step
curl -v -A "$UA" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -L -X POST "https://service.thecloud.eu/service-platform/macauthlogin/v5/registration" >> "$LOG_FILE" 2>&1

echo "Checking internet connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 > /dev/null && echo "Login successful and internet is reachable." | tee -a "$LOG_FILE" || { echo "Login failed or no internet." | tee -a "$LOG_FILE"; exit 1; }