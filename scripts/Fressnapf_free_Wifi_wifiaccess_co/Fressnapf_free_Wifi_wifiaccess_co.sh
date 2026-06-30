#!/bin/bash
LOG_FILE="/tmp/wifi_login.log"
echo "Starting Portal Login Script..." | tee -a "$LOG_FILE"

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

# 2. Extract Portal URL
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE="/tmp/portal_cookies.txt"

echo "Fetching initial redirect..." | tee -a "$LOG_FILE"
REDIRECT_URL=$(curl -v -A "$USER_AGENT" -c "$COOKIE_FILE" -o /dev/null -w "%{redirect_url}" "http://connectivity-check.ubuntu.com/" 2>&1 | sed -n 's/.*Location: //p' | tr -d '\r' | head -n 1)
[ -z "$REDIRECT_URL" ] && REDIRECT_URL="https://wifiaccess.co/103/portal/"

# 3. Get API Endpoint
API_URL=$(echo "$REDIRECT_URL" | sed 's|/portal/.*|/portal_api.php|')
echo "Target API URL: $API_URL" | tee -a "$LOG_FILE"

# 4. Initialize Session
# Captive portal uses JS to call 'init' action on portal_api.php
echo "Initializing session..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -d "action=init" "$API_URL")
echo "HTTP Response: $RESPONSE" | tee -a "$LOG_FILE"

# 5. Authenticate (Free Wi-Fi access usually requires empty fields or policy acceptance)
# Based on portal JS: logonFormConnect calls authenticate action
echo "Submitting connection..." | tee -a "$LOG_FILE"
AUTH_RESPONSE=$(curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
    -d "action=authenticate" \
    -d "login=" \
    -d "password=" \
    -d "policy_accept=true" \
    "$API_URL")
echo "Auth Response: $AUTH_RESPONSE" | tee -a "$LOG_FILE"

# 6. Final Connectivity Check
echo "Performing final connectivity check..." | tee -a "$LOG_FILE"
sleep 5
ping -c 3 8.8.8.8 >> "$LOG_FILE" 2>&1 && { echo "SUCCESS: Internet access confirmed."; exit 0; } || { echo "FAILURE: No internet access."; exit 1; }