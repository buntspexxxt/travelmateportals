#!/bin/bash

LOG_FILE="/tmp/portal_log.txt"
COOKIE_FILE="/tmp/cookies.txt"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Starting RRX_Hotspot automation..." | tee -a "$LOG_FILE"

# 1. Wait for network
echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found!" | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

# 2. Trigger initial portal check and capture redirect parameters
echo "Triggering captive portal redirect..." | tee -a "$LOG_FILE"
# We fetch the URL that causes the redirect, ensuring we grab the full Location string with all params
REDIRECT_URL=$(curl -v -A "$USER_AGENT" -c "$COOKIE_FILE" http://neverssl.com/online 2>&1 | grep -i "Location:" | tail -n 1 | sed -n 's/.*Location: //p' | tr -d '\r')

echo "Initial Redirect URL: $REDIRECT_URL" | tee -a "$LOG_FILE"

# 3. Access the Landing Page (which contains the 'Online gehen' link)
echo "Accessing landing page to fetch session parameters..." | tee -a "$LOG_FILE"
curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -L "$REDIRECT_URL" > /tmp/portal_html.html 2>&1

# 4. Handle the 'prelogin' step found in the HTML
# The HTML indicates a link: <a href="http://192.168.44.1/prelogin" class="btn btn-primary btn-lg">Online gehen</a>
# We follow this link to finalize the authentication.
PRELOGIN_URL="http://192.168.44.1/prelogin"
echo "Navigating to $PRELOGIN_URL to initiate session..." | tee -a "$LOG_FILE"
curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -L "$PRELOGIN_URL" > /tmp/post_login.html 2>&1

# 5. Check if further Hotsplots auth is required (common in CoovaChilli setups)
# If there is a form remaining, submit it.
FORM_ACTION=$(grep -oP 'action="\K[^"]+' /tmp/post_login.html | head -1)
if [ -n "$FORM_ACTION" ]; then
    echo "Found remaining form at $FORM_ACTION, submitting..." | tee -a "$LOG_FILE"
    curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -X POST "$FORM_ACTION" -d "accept=true&connect=Login" >> "$LOG_FILE" 2>&1
fi

# 6. Final connectivity check
echo "Verifying internet connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Successfully connected." | tee -a "$LOG_FILE" && exit 0 || { echo "Failed to connect."; exit 1; }