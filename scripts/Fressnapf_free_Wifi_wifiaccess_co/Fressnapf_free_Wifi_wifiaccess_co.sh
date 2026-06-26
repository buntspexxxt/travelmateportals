#!/bin/bash

LOG_FILE="/tmp/portal_login.log"
echo "--- Starting Ucopia Portal Login Script ---" | tee -a "$LOG_FILE"

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

echo "Fetching portal index to initialize session and get API endpoint..." | tee -a "$LOG_FILE"
curl -v -A "$UA" -c "$COOKIE_FILE" -b "$COOKIE_FILE" https://wifiaccess.co/103/portal/ > /tmp/index.html 2>&1

echo "Initializing API session..." | tee -a "$LOG_FILE"
# Extracting the controller hostname from the meta/js or assume root URL
RESPONSE=$(curl -v -A "$UA" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -d "action=init" https://wifiaccess.co/portal_api.php)
echo "HTTP Response: $RESPONSE" | tee -a "$LOG_FILE"

echo "Authenticating with blank credentials (Accepting terms)..." | tee -a "$LOG_FILE"
# Ucopia portals usually require these fields to proceed
AUTH_RESPONSE=$(curl -v -A "$UA" -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
    -d "action=authenticate" \
    -d "login=" \
    -d "password=" \
    -d "policy_accept=true" \
    https://wifiaccess.co/portal_api.php)

echo "Authentication Status: $AUTH_RESPONSE" | tee -a "$LOG_FILE"

sleep 5
echo "Performing final connectivity check..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "SUCCESS: Internet is reachable." | tee -a "$LOG_FILE" && exit 0 || { echo "FAILURE: No internet connection." | tee -a "$LOG_FILE"; exit 1; }