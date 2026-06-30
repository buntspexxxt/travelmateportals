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

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE="/tmp/portal_cookies.txt"

# 2. Extract base URL dynamically
echo "Fetching landing page to extract branch ID and session..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -v -A "$USER_AGENT" -c "$COOKIE_FILE" -L "https://wifiaccess.co/" 2>&1)
EFFECTIVE_URL=$(echo "$RESPONSE" | grep "Location:" | sed -n 's/.*Location: //p' | tr -d '\r' | tail -1)
if [ -z "$EFFECTIVE_URL" ]; then EFFECTIVE_URL="https://wifiaccess.co/103/portal/"; fi
BASE_URL=$(echo "$EFFECTIVE_URL" | cut -d'/' -f1-5)
API_URL="${BASE_URL}/portal_api.php"
echo "API Endpoint: $API_URL" | tee -a "$LOG_FILE"

# 3. Initialize Session
echo "Initializing session..." | tee -a "$LOG_FILE"
curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -d "action=init" "$API_URL" >> "$LOG_FILE" 2>&1

# 4. Authenticate (Policy Acceptance)
echo "Submitting authentication..." | tee -a "$LOG_FILE"
AUTH_RESPONSE=$(curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
    -d "action=authenticate" \
    -d "login=" \
    -d "password=" \
    -d "policy_accept=true" \
    -d "private_policy_accept=true" \
    "$API_URL")
echo "Auth Response: $AUTH_RESPONSE" | tee -a "$LOG_FILE"

# 5. Check if further input needed
if [[ "$AUTH_RESPONSE" == *"logonForm"* ]]; then
    echo "Portal requires explicit form submission. Attempting standard accept..." | tee -a "$LOG_FILE"
    curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -d "action=authenticate&login=&password=&policy_accept=true" "$API_URL" >> "$LOG_FILE" 2>&1
fi

# 6. Final Connectivity Check
echo "Performing final connectivity check..." | tee -a "$LOG_FILE"
sleep 5
ping -c 3 8.8.8.8 >> "$LOG_FILE" 2>&1 && { echo "SUCCESS: Internet access confirmed."; exit 0; } || { echo "FAILURE: No internet access."; exit 1; }