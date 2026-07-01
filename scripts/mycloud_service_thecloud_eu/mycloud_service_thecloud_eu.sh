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

echo "Fetching portal page to obtain session cookies and form details..."
PAGE_CONTENT=$(curl -v -A "$UA" -c "$COOKIE_FILE" "https://service.thecloud.eu/service-platform/macauthlogin/v5" 2>&1)
RESPONSE_CODE=$(echo "$PAGE_CONTENT" | grep "HTTP/" | tail -1 | awk '{print $2}')
echo "HTTP Response: $RESPONSE_CODE"

# The Cloud typically requires a simple POST to their registration endpoint after clicking the form button.
echo "Submitting registration/login form..."
LOGIN_RESPONSE=$(curl -v -A "$UA" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -L "https://service.thecloud.eu/service-platform/macauthlogin/v5/registration" \
    -X POST \
    -d "submit=Continue" 2>&1)

echo "Full Login response captured. Checking for success..."
echo "$LOGIN_RESPONSE" | grep -q "HTTP/" && echo "Submitted successfully."

echo "Verifying internet connectivity..."
ping -c 3 8.8.8.8 >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "Login successful: Internet access confirmed."
    exit 0
else
    echo "Login failed: No internet access detected."
    exit 1
fi