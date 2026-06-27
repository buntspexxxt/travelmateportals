#!/bin/bash
LOG_FILE="/tmp/portal_log.txt"
COOKIE_FILE="/tmp/portal_cookies.txt"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Waiting for DHCP..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

echo "Initiating connection..." | tee -a "$LOG_FILE"
REDIRECT_URL=$(curl -A "$USER_AGENT" -c "$COOKIE_FILE" -L "http://connectivitycheck.gstatic.com/generate_204" -v 2>&1 | grep "Location:" | tail -n 1 | awk '{print $2}' | tr -d '\r')
BASE_URL=$(echo "$REDIRECT_URL" | cut -d'/' -f1-4)
echo "Detected Base URL: $BASE_URL" | tee -a "$LOG_FILE"

# Initialize Session
curl -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$BASE_URL/" >> "$LOG_FILE" 2>&1

# API Initialization
API_URL="$BASE_URL/portal_api.php"
echo "Calling API Init..." | tee -a "$LOG_FILE"
curl -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -d "action=init" "$API_URL" >> "$LOG_FILE" 2>&1

# First Step: Accept Policy
echo "Submitting policy acceptance..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -d "action=authenticate&policy_accept=true&secure_pwd=" "$API_URL" 2>&1)
echo "Auth Response: $RESPONSE" | tee -a "$LOG_FILE"

# Second Step: Handle LogonForm/Subscription
# If the portal requires user interaction (like clicking connect), we attempt an empty login
echo "Submitting empty credentials for free access..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -d "action=authenticate&login=&password=&policy_accept=true&secure_pwd=" "$API_URL" 2>&1)
echo "Final Auth Response: $RESPONSE" | tee -a "$LOG_FILE"

echo "Verifying internet access..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Successfully connected!" && exit 0 || echo "Connection failed." && exit 1