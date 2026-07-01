#!/bin/bash

LOG_FILE="/tmp/portal_login.log"
echo "Starting WiFi4EU login process..." | tee -a "$LOG_FILE"

# 1. Wait for network initialization
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
COOKIE_JAR="/tmp/wifi_cookies.txt"

# 2. Get the redirect and session cookie
echo "Initial request to detect portal..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -v -A "$USER_AGENT" -c "$COOKIE_JAR" -L "http://detectportal.firefox.com/success.txt" 2>&1)
echo "HTTP Response details captured." | tee -a "$LOG_FILE"

# 3. Extract the 'Get Online' link
echo "Extracting 'Get Online' URL..." | tee -a "$LOG_FILE"
GET_ONLINE_URL=$(echo "$RESPONSE" | grep -oE 'href="[^"]*/service-platform/url/[0-9]+"' | head -1 | sed 's/href="//;s/"//')

if [ -z "$GET_ONLINE_URL" ]; then
    echo "Error: Could not find 'Get Online' link. Exiting." | tee -a "$LOG_FILE"
    exit 1
fi

# 4. Navigate to the activation URL to finalize
echo "Accessing activation URL: $GET_ONLINE_URL" | tee -a "$LOG_FILE"
ACTIVATION_RESULT=$(curl -v -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" -L "$GET_ONLINE_URL" 2>&1)

# 5. Final connectivity test
echo "Connectivity test..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Login successful!" | tee -a "$LOG_FILE" || { echo "Login failed or no internet access." | tee -a "$LOG_FILE"; exit 1; }
exit 0