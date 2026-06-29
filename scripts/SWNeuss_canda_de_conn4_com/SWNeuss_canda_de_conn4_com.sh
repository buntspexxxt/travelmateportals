#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
echo "Starting Captive Portal Login..." | tee -a "$LOG_FILE"

echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

echo "Fetching initial redirect to identify grant_url..." | tee -a "$LOG_FILE"
REDIRECT_RESPONSE=$(curl -v -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -L "http://detectportal.firefox.com/success.txt" 2>&1)

# Extract the final URL which contains the grant_url parameter
GRANT_URL=$(echo "$REDIRECT_RESPONSE" | grep -oP '(?<=Location: )https://eu\.network-auth\.com/splash/[^/]+/grant' | head -n 1 | tr -d '\r')

if [ -z "$GRANT_URL" ]; then
    echo "Failed to extract GRANT_URL from redirect headers." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Found Grant URL: $GRANT_URL" | tee -a "$LOG_FILE"
echo "Performing POST request to grant access..." | tee -a "$LOG_FILE"

# Performing the grant request
RESPONSE=$(curl -v -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -X POST "$GRANT_URL" -d "button=Click+to+Connect" 2>&1)

echo "HTTP Response Received." | tee -a "$LOG_FILE"

echo "Performing final connectivity check..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Connectivity confirmed! Login successful." || { echo "Login failed or no internet access."; exit 1; }