#!/bin/bash

LOG_FILE="/tmp/portal_log.txt"
echo "Starting RRX_Hotspot automation script..." | tee -a "$LOG_FILE"

# 1. Wait for network
echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

# 2. Trigger the portal redirect by hitting an unencrypted site
echo "Attempting to trigger portal redirect via http://neverssl.com" | tee -a "$LOG_FILE"
REDIRECT_URL=$(curl -v -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" http://neverssl.com/ 2>&1 | grep -i "Location:" | head -n 1 | sed -n 's/.*Location: //p' | tr -d '\r')

echo "Redirect URL extracted: $REDIRECT_URL" | tee -a "$LOG_FILE"

# 3. Handle the multi-page nature
echo "Attempting to reach the Hotspots login page..." | tee -a "$LOG_FILE"
# We use the cookie jar to maintain session state across the multi-step process
curl -v -c /tmp/cookies.txt -b /tmp/cookies.txt -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" "$REDIRECT_URL" > /tmp/portal_page.html 2>&1

# 4. Check for and submit the login form if it exists
# Extract form action and required hidden fields
FORM_ACTION=$(grep -oP 'action="\K[^"]+' /tmp/portal_page.html | head -1)
if [ -n "$FORM_ACTION" ]; then
    echo "Found login form at $FORM_ACTION, attempting to accept terms..." | tee -a "$LOG_FILE"
    # Example: Most public hotspots use a 'accept' or 'login' parameter with empty credentials
    curl -v -c /tmp/cookies.txt -b /tmp/cookies.txt -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -X POST "$FORM_ACTION" -d "accept=true&login=Login" >> "$LOG_FILE" 2>&1
fi

# 5. Final connectivity check
echo "Performing final connectivity check..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Successfully connected to internet." | tee -a "$LOG_FILE" && exit 0 || { echo "Failed to reach internet."; exit 1; }