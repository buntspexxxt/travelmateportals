#!/bin/bash
LOG_FILE="/tmp/wifi_login.log"
echo "Starting Portal Login Script..." | tee -a "$LOG_FILE"

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

echo "Fetching initial portal page..." | tee -a "$LOG_FILE"
curl -v -A "$USER_AGENT" -c "$COOKIE_FILE" -L "https://wifiaccess.co/103/portal/" -o /dev/null >> "$LOG_FILE" 2>&1

# The Ucopia portal architecture (103/portal) uses a portal_api.php script for logic
BASE_URL="https://wifiaccess.co/103/portal"
API_URL="https://wifiaccess.co/103/portal_api.php"

echo "Initializing session via API..." | tee -a "$LOG_FILE"
curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -d "action=init" "$API_URL" >> "$LOG_FILE" 2>&1

echo "Submitting authentication..." | tee -a "$LOG_FILE"
# Ucopia portals usually require policy_accept=true for free guest access
AUTH_RESPONSE=$(curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
    -d "action=authenticate" \
    -d "login=" \
    -d "password=" \
    -d "policy_accept=true" \
    "$API_URL")
echo "Auth Response: $AUTH_RESPONSE" | tee -a "$LOG_FILE"

# Check if an additional 'secure_pwd' or specific form submission is needed if the above returns an error
if echo "$AUTH_RESPONSE" | grep -q "error"; then
    echo "Initial auth returned error, attempting secondary handshake..." | tee -a "$LOG_FILE"
    curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
        -d "action=authenticate" \
        -d "login=" \
        -d "password=" \
        -d "policy_accept=true" \
        -d "secure_pwd=" \
        "$API_URL" >> "$LOG_FILE" 2>&1
fi

echo "Performing final connectivity check..." | tee -a "$LOG_FILE"
sleep 5
ping -c 3 8.8.8.8 >> "$LOG_FILE" 2>&1 && { echo "SUCCESS: Internet access confirmed."; exit 0; } || { echo "FAILURE: No internet access."; exit 1; }