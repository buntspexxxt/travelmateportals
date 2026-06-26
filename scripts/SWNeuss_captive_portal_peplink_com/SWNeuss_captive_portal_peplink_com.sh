#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
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
COOKIE_FILE="/tmp/cp_cookies.txt"

echo "Initial check for captive portal redirect..." | tee -a "$LOG_FILE"
REDIRECT_RESPONSE=$(curl -v -L -A "$USER_AGENT" -c "$COOKIE_FILE" "http://detectportal.firefox.com/success.txt" 2>&1)
echo "Response: $REDIRECT_RESPONSE" | tee -a "$LOG_FILE"

# Extract base URL and parameters from the initial request
# The portal logic uses a session resume API check
API_URL="https://guest7.ic.peplink.com/cp/session/resume"
echo "Attempting to resume session via Peplink API..." | tee -a "$LOG_FILE"

# We need the parameters from the initial landing page URL provided in logs
# Extracting params dynamically using grep/sed
QUERY_PARAMS=$(echo "$REDIRECT_RESPONSE" | grep -oE "checksum=[^&]+\S+" | head -n 1 | sed 's/"//g')

# Perform the API check to see if we can jump straight to login
API_RESPONSE=$(curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$API_URL?$QUERY_PARAMS" 2>&1)
echo "API Response: $API_RESPONSE" | tee -a "$LOG_FILE"

# If resume fails, the portal redirects to /login.html
# The JS logic indicates a simple formless POST or redirect with params
echo "Triggering connection via login redirect..." | tee -a "$LOG_FILE"
LOGIN_URL="https://guest7.ic.peplink.com/cp/login?$QUERY_PARAMS"
curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" "$LOGIN_URL" | tee -a "$LOG_FILE"

echo "Connectivity check..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Connected!" && exit 0 || exit 1