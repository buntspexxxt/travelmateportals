#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE="/tmp/portal_cookies.txt"

echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

echo "Fetching initial portal page to obtain session cookies..."
curl -v -A "$UA" -c "$COOKIE_FILE" "https://service.thecloud.eu/service-platform/macauthlogin/v5" > /dev/null 2>&1

echo "Submitting initial registration form..."
# Submit initial form to proceed to confirmation or next state
SUBMIT_RESPONSE=$(curl -v -A "$UA" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -L "https://service.thecloud.eu/service-platform/macauthlogin/v5/registration" \
    -X POST \
    -d "submit=Continue" 2>&1)

echo "HTTP Response from registration: $SUBMIT_RESPONSE"

echo "Checking if secondary action is required..."
# Check if session needs a final trigger or if navigation is complete
# Based on analysis, sometimes a final GET is required if the POST is an API transition
curl -v -A "$UA" -b "$COOKIE_FILE" "https://service.thecloud.eu/service-platform/home" > /dev/null 2>&1

echo "Verifying internet connectivity..."
ping -c 3 8.8.8.8 >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "Login successful: Internet access confirmed."
    exit 0
else
    echo "Login failed: No internet access detected. Retrying..."
    sleep 5
    ping -c 3 8.8.8.8 >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "Login successful after retry."
        exit 0
    fi
    echo "Login failed: No internet access detected."
    exit 1
fi