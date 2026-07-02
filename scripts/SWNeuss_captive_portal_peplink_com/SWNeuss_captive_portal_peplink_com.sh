#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
echo "Starting Captive Portal Login Script" | tee -a "$LOG_FILE"

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

echo "Fetching initial portal page to extract session parameters..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -v -A "$USER_AGENT" -c /tmp/cookies.txt http://detectportal.firefox.com/success.txt 2>&1)
echo "HTTP Response captured." | tee -a "$LOG_FILE"

# Extract the redirect URL from the Location header
REDIRECT_URL=$(echo "$RESPONSE" | sed -n 's/.*Location: //p' | tr -d '\r')
echo "Redirect URL extracted: $REDIRECT_URL" | tee -a "$LOG_FILE"

# The Peplink portal uses a 'session/resume' API endpoint based on the JS analysis
# Extract parameters from the redirect URL to reconstruct the JSON POST/GET
QUERY_STRING=$(echo "$REDIRECT_URL" | cut -d'?' -f2)

echo "Attempting to resume session via API..." | tee -a "$LOG_FILE"
# The JS logic indicates a GET call to /cp/session/resume with query params
RESUME_URL="https://guest7.ic.peplink.com/cp/session/resume?$QUERY_STRING"
JSON_RESPONSE=$(curl -v -A "$USER_AGENT" -b /tmp/cookies.txt "$RESUME_URL")
echo "Resume Response: $JSON_RESPONSE" | tee -a "$LOG_FILE"

# If session resume fails, the JS calls toDeviceLogin() which redirects to the login page
echo "Triggering final login sequence..." | tee -a "$LOG_FILE"
# Based on the JS, the command to finalize is a POST/Redirect to /cp/login
LOGIN_URL="https://guest7.ic.peplink.com/cp/login?$QUERY_STRING&command=login"
FINAL_RESPONSE=$(curl -v -A "$USER_AGENT" -b /tmp/cookies.txt "$LOGIN_URL")
echo "Final Login Status: $FINAL_RESPONSE" | tee -a "$LOG_FILE"

echo "Checking connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Connectivity confirmed." && exit 0 || exit 1