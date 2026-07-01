#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE="/tmp/portal_cookies.txt"

echo "Starting login script for mycloud / The Cloud..." | tee -a "$LOG_FILE"

# 1. Wait for DHCP (IP & Gateway)
echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

# Check if already online
if ping -c 3 8.8.8.8 >/dev/null 2>&1; then
    echo "Already online. Exiting." | tee -a "$LOG_FILE"
    exit 0
fi

# 2. Start from neverssl.com and follow all redirects to landing page
echo "Following redirect chain from neverssl.com to establish session..." | tee -a "$LOG_FILE"
rm -f "$COOKIE_FILE"
LANDING_URL=$(curl -v -L -k -A "$UA" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -w "%{url_effective}" -o /dev/null http://neverssl.com 2>/dev/null)
echo "Landing URL obtained: $LANDING_URL" | tee -a "$LOG_FILE"

# 3. POST to the registration endpoint using the session cookies
echo "Submitting form to registration endpoint..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -v -k -A "$UA" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -L "https://service.thecloud.eu/service-platform/macauthlogin/v5/registration" \
    -X POST \
    -d "submit=Continue" 2>&1)

echo "Response from submission: $RESPONSE" | tee -a "$LOG_FILE"

# 4. Connectivity check
echo "Checking internet connectivity..." | tee -a "$LOG_FILE"
sleep 5
ping -c 3 8.8.8.8 >/dev/null && { echo "Success: Internet access restored."; rm -f "$COOKIE_FILE"; exit 0; } || {
    echo "Trying fallback login to wbs API..." | tee -a "$LOG_FILE"
    curl -v -k -A "$UA" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -X POST "https://service.thecloud.eu/service-platform/macauthlogin/v5/registration" >> "$LOG_FILE" 2>&1
    sleep 5
    ping -c 3 8.8.8.8 >/dev/null && { echo "Success on fallback!"; rm -f "$COOKIE_FILE"; exit 0; }
}

echo "Error: Connectivity test failed." | tee -a "$LOG_FILE"
rm -f "$COOKIE_FILE"
exit 1
