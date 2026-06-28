#!/bin/bash

LOG_FILE="/tmp/wifi_login.log"
echo "Starting login process..." | tee -a "$LOG_FILE"

# 1. Wait for DHCP
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

# 2. Access login page to capture cookies and form action
echo "Fetching portal page..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -v -c /tmp/cookies.txt -A "$USER_AGENT" -L "https://service.thecloud.eu/service-platform/macauthlogin/v5" 2>&1)
echo "HTTP Response Check: $RESPONSE" | tee -a "$LOG_FILE"

# 3. Submit form
# The portal uses a simple POST to registration. Based on the HTML, it is a 'one-click' style login.
echo "Submitting registration form..." | tee -a "$LOG_FILE"
POST_RESPONSE=$(curl -v -b /tmp/cookies.txt -c /tmp/cookies.txt -A "$USER_AGENT" \\
  -d "terms=on" \\
  "https://service.thecloud.eu/service-platform/macauthlogin/v5/registration" 2>&1)
echo "Submission result: $POST_RESPONSE" | tee -a "$LOG_FILE"

# 4. Connectivity Check
echo "Running connectivity check..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Login successful!" && exit 0 || { echo "Login failed."; exit 1; }