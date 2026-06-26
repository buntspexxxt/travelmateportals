#!/bin/bash

LOG_FILE="/tmp/portal_login.log"
echo "--- Starting Ucopia Portal Login Script v2 ---" | tee -a "$LOG_FILE"

# Wait for network
echo "Waiting for DHCP..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then echo "Gateway found."; break; fi
    sleep 1
done

UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE="/tmp/portal_cookies.txt"

# 1. Initialize Portal
echo "Initializing portal session..." | tee -a "$LOG_FILE"
INDEX_RESPONSE=$(curl -v -A "$UA" -c "$COOKIE_FILE" -b "$COOKIE_FILE" https://wifiaccess.co/103/portal/)

# Extract Controller Host from the JS or Meta if needed, but for now we target the API base
API_URL="https://wifiaccess.co/portal_api.php"

# 2. Get Init Data
echo "Sending init action..." | tee -a "$LOG_FILE"
curl -v -A "$UA" -b "$COOKIE_FILE" -d "action=init" "$API_URL"

# 3. Handle Login (The portal has a 'securePwdForm')
# Based on analysis, this form requires an 'secure_pwd' (often blank or specific to store)
# Attempting standard authentication with policy acceptance
echo "Authenticating with policy acceptance..." | tee -a "$LOG_FILE"
AUTH_RESULT=$(curl -v -A "$UA" -b "$COOKIE_FILE" -d "action=authenticate" -d "login=" -d "password=" -d "policy_accept=true" "$API_URL")
echo "Result: $AUTH_RESULT" | tee -a "$LOG_FILE"

# 4. Check if portal demands more
# If AUTH_RESULT contains error_login, try the 'securePwdForm' logic
if echo "$AUTH_RESULT" | grep -q "error"; then
    echo "Detected authentication error, trying secure password submission..." | tee -a "$LOG_FILE"
    # Some Ucopia portals use the 'secure_pwd' field for basic store-wide passwords
    curl -v -A "$UA" -b "$COOKIE_FILE" -d "action=secure_pwd" -d "secure_pwd=" "$API_URL"
    # Retry auth after unlocking portal
    curl -v -A "$UA" -b "$COOKIE_FILE" -d "action=authenticate" -d "login=" -d "password=" -d "policy_accept=true" "$API_URL"
fi

echo "Finalizing..." | tee -a "$LOG_FILE"
sleep 5
ping -c 3 8.8.8.8 >/dev/null && echo "SUCCESS" || exit 1