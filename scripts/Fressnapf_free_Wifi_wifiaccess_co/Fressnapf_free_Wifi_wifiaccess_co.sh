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

# 2. Fetch Initial Session
echo "Fetching initial portal page..." | tee -a "$LOG_FILE"
curl -v -A "$USER_AGENT" -c "$COOKIE_FILE" -L "https://wifiaccess.co/103/portal/" -o /dev/null >> "$LOG_FILE" 2>&1

# 3. API Handshake
API_URL="https://wifiaccess.co/103/portal_api.php"
echo "Initializing session via API..." | tee -a "$LOG_FILE"
curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -d "action=init" "$API_URL" >> "$LOG_FILE" 2>&1

# 4. Authenticate with Policy Acceptance (as per hint)
echo "Submitting authentication with policy acceptance..." | tee -a "$LOG_FILE"
AUTH_RESPONSE=$(curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" \\
    -d "action=authenticate" \\
    -d "login=" \\
    -d "password=" \\
    -d "policy_accept=true" \\
    -d "private_policy_accept=true" \\
    "$API_URL")
echo "Auth Response: $AUTH_RESPONSE" | tee -a "$LOG_FILE"

# 5. Connectivity check
echo "Performing final connectivity check..." | tee -a "$LOG_FILE"
sleep 5
ping -c 3 8.8.8.8 >> "$LOG_FILE" 2>&1 && { echo "SUCCESS: Internet access confirmed."; exit 0; } || { echo "FAILURE: No internet access."; exit 1; }