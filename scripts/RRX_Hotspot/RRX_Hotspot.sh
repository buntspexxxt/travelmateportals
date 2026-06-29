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

# 2. Trigger initial portal redirect to HotSplots
echo "Triggering redirect..." | tee -a "$LOG_FILE"
# We fetch http://neverssl.com/online to force the HotSplots login page redirect
REDIRECT_URL=$(curl -v -L -A "$USER_AGENT" -c "$COOKIE_FILE" http://neverssl.com/online 2>&1 | grep -i "Location:" | tail -n 1 | sed -n 's/.*Location: //p' | tr -d '\r')

echo "Detected portal URL: $REDIRECT_URL" | tee -a "$LOG_FILE"

# 3. Handle the HotSplots login page
# According to Hotsplots design, we need to POST the login form to reach the landing/accept page.
echo "Fetching login page..." | tee -a "$LOG_FILE"
curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -L "$REDIRECT_URL" > /tmp/portal_html.html 2>&1

# Extract form action and submit standard accept
FORM_ACTION=$(grep -oP 'action="\K[^"]+' /tmp/portal_html.html | head -1)
if [ -n "$FORM_ACTION" ]; then
    echo "Submitting form to $FORM_ACTION..." | tee -a "$LOG_FILE"
    # Hotsplots usually requires an 'accept' parameter. We POST an empty login attempt to trigger session approval.
    curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -X POST "$FORM_ACTION" -d "accept=true&connect=Login" >> "$LOG_FILE" 2>&1
else
    echo "No specific form found, assuming auto-login or session established." | tee -a "$LOG_FILE"
fi

# 4. Final connectivity check
echo "Verifying connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Successfully connected." | tee -a "$LOG_FILE" && exit 0 || { echo "Failed to connect."; exit 1; }