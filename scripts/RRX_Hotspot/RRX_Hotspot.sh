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

# 2. Trigger the portal redirect
echo "Attempting to trigger portal redirect via http://neverssl.com" | tee -a "$LOG_FILE"
# We use -v to observe headers and -o to discard body content while identifying the redirect target
REDIRECT_URL=$(curl -v -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" http://neverssl.com/ 2>&1 | grep -i "Location:" | tail -n 1 | sed -n 's/.*Location: //p' | tr -d '\r')

echo "Redirect URL extracted: $REDIRECT_URL" | tee -a "$LOG_FILE"

# 3. Handle the multi-page nature
echo "Reaching the Hotspots login page..." | tee -a "$LOG_FILE"
curl -v -c /tmp/cookies.txt -b /tmp/cookies.txt -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" "$REDIRECT_URL" > /tmp/portal_page.html 2>&1

# 4. Extract form and submit
# The provided HTML indicates an intermediate step. We search for the hidden inputs in the result.
FORM_ACTION=$(grep -oP 'action="\K[^"]+' /tmp/portal_page.html | head -1)
if [ -n "$FORM_ACTION" ]; then
    echo "Found login form at $FORM_ACTION, submitting credentials..." | tee -a "$LOG_FILE"
    # As per instructions, no specific credentials are required (accept terms only)
    curl -v -c /tmp/cookies.txt -b /tmp/cookies.txt -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -X POST "$FORM_ACTION" -d "accept=true&submit=Continue" >> "$LOG_FILE" 2>&1
else
    echo "No login form found; assuming auto-redirection or session already active." | tee -a "$LOG_FILE"
fi

# 5. Final connectivity check
echo "Performing final connectivity check..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Successfully connected to internet." | tee -a "$LOG_FILE" && exit 0 || { echo "Failed to reach internet."; exit 1; }