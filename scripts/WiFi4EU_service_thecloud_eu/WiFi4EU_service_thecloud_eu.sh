#!/bin/bash

LOG_FILE="/tmp/portal_login.log"
echo "Starting WiFi4EU login process..." | tee -a "$LOG_FILE"

# 1. Wait for DHCP
echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_JAR="/tmp/wifi_cookies.txt"

# 2. Get initial page to set session
echo "Initial request to platform..." | tee -a "$LOG_FILE"
PAGE_HTML=$(curl -v -A "$USER_AGENT" -c "$COOKIE_JAR" -L "https://service.thecloud.eu/service-platform/home" 2>&1)

# 3. Extract the 'Get Online' URL dynamically
# The portal requires hitting the specific URL path for the 'Get Online' link found in the HTML
GET_ONLINE_URL=$(echo "$PAGE_HTML" | sed -n 's/.*href="\([^"]*\/service-platform\/url\/[0-9]\+\)".*/\1/p' | head -1)

if [ -z "$GET_ONLINE_URL" ]; then
    echo "Error: Could not find 'Get Online' link. Exiting." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Navigating to activation link: $GET_ONLINE_URL" | tee -a "$LOG_FILE"

# 4. Perform the activation
# We follow the redirect to the final authorization page
RESULT=$(curl -v -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" -L "$GET_ONLINE_URL" 2>&1)

# 5. Check if we need to interact with the second stage (Terms/Acceptance)
# The portal structure suggests the final authentication is finalized after this request.
echo "Verifying internet access..." | tee -a "$LOG_FILE"

# 6. Connectivity check
ping -c 3 8.8.8.8 >/dev/null && {
    echo "Login successful!" | tee -a "$LOG_FILE"
    exit 0
} || {
    echo "Login failed or no internet access." | tee -a "$LOG_FILE"
    exit 1
}