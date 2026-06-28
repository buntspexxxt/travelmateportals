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

echo "Fetching portal home page to obtain session cookie..." | tee -a "$LOG_FILE"
curl -v -A "$UA" -c "$COOKIE_FILE" "https://service.thecloud.eu/service-platform/home" > /dev/null 2>&1

echo "Extracting 'Get Online' link from portal page..." | tee -a "$LOG_FILE"
LOGIN_URL=$(curl -v -A "$UA" -b "$COOKIE_FILE" "https://service.thecloud.eu/service-platform/home" 2>&1 | grep -o 'https://service.thecloud.eu/service-platform/url/[0-9]*' | head -n 1)

if [ -z "$LOGIN_URL" ]; then
    echo "Error: Could not find login URL."
    exit 1
fi

echo "Proceeding to login URL: $LOGIN_URL" | tee -a "$LOG_FILE"
RESPONSE=$(curl -v -A "$UA" -b "$COOKIE_FILE" -L -o /dev/null -w "%{http_code}" "$LOGIN_URL")
echo "HTTP Response: $RESPONSE" | tee -a "$LOG_FILE"

echo "Checking internet connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 > /dev/null && echo "Login successful and internet is reachable." || echo "Login failed or no internet."
exit 0