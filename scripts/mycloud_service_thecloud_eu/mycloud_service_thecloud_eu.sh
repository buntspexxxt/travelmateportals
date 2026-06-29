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
# Get initial session
curl -v -A "$UA" -c "$COOKIE_FILE" -L "https://service.thecloud.eu/service-platform/home" > /dev/null 2>&1

echo "Extracting 'Get Online' URL..." | tee -a "$LOG_FILE"
# The 'Get Online' link is dynamic, we need to extract its href from the home page
GET_ONLINE_URL=$(curl -v -A "$UA" -b "$COOKIE_FILE" "https://service.thecloud.eu/service-platform/home" | grep -o 'https://service.thecloud.eu/service-platform/url/[0-9]*' | head -1)

if [ -z "$GET_ONLINE_URL" ]; then
    echo "Failed to extract 'Get Online' URL. Aborting." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Found URL: $GET_ONLINE_URL. Navigating..." | tee -a "$LOG_FILE"
# Follow the specific URL to trigger the activation process
FINAL_REDIRECT=$(curl -v -A "$UA" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -L -o /dev/null -w "%{url_effective}" "$GET_ONLINE_URL")
echo "Redirected to: $FINAL_REDIRECT" | tee -a "$LOG_FILE"

echo "Checking internet connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 > /dev/null && echo "Login successful and internet is reachable." | tee -a "$LOG_FILE" || { echo "Login failed or no internet." | tee -a "$LOG_FILE"; exit 1; }