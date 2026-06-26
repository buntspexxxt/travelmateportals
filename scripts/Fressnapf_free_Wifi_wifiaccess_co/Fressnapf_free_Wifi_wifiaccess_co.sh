#!/bin/bash

LOG_FILE="/tmp/portal_login.log"
echo "--- Starting Enhanced Ucopia Portal Login ---" | tee -a "$LOG_FILE"

echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE="/tmp/portal_cookies.txt"

echo "Initializing session..." | tee -a "$LOG_FILE"
curl -v -A "$UA" -c "$COOKIE_FILE" -b "$COOKIE_FILE" "https://wifiaccess.co/103/portal/" | tee -a "$LOG_FILE"

API_URL="https://wifiaccess.co/portal_api.php"

echo "Fetching portal configuration..." | tee -a "$LOG_FILE"
INIT_RESP=$(curl -v -A "$UA" -b "$COOKIE_FILE" -d "action=init" "$API_URL")
echo "Init Response: $INIT_RESP" | tee -a "$LOG_FILE"

echo "Authenticating with policy acceptance..." | tee -a "$LOG_FILE"
# Using policy_accept=on as per requirement
AUTH_RESP=$(curl -v -A "$UA" -b "$COOKIE_FILE" -d "action=authenticate" -d "login=" -d "password=" -d "policy_accept=on" "$API_URL")
echo "Auth Response: $AUTH_RESP" | tee -a "$LOG_FILE"

if echo "$AUTH_RESP" | grep -q "error"; then
    echo "Error detected, attempting secure_pwd bypass..." | tee -a "$LOG_FILE"
    curl -v -A "$UA" -b "$COOKIE_FILE" -d "action=secure_pwd" -d "secure_pwd=" "$API_URL" | tee -a "$LOG_FILE"
    echo "Retrying authentication..." | tee -a "$LOG_FILE"
    curl -v -A "$UA" -b "$COOKIE_FILE" -d "action=authenticate" -d "login=" -d "password=" -d "policy_accept=on" "$API_URL" | tee -a "$LOG_FILE"
fi

echo "Final connectivity check..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "SUCCESS" || exit 1