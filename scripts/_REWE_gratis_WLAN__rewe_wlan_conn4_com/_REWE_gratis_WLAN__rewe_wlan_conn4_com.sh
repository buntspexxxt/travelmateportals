#!/bin/bash

LOG_FILE="/tmp/wifi_login.log"
COOKIE_JAR="/tmp/cookies.txt"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

echo "Fetching initial portal page to extract session and tokens..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -v -A "$USER_AGENT" -c "$COOKIE_JAR" -b "$COOKIE_JAR" https://rewe-wlan.conn4.com/ 2>&1)

# The portal logic uses a client-side JS scene loader. 
# Based on the HTML, it checks for a 'wbsToken' in the JavaScript context.
# Since this is a simple 'accept terms' style landing, hitting the root often triggers the session.

echo "Sending secondary navigation to ensure session registration..." | tee -a "$LOG_FILE"
# Simulate the browser navigation to the return URL found in the XML comment
curl -v -A "$USER_AGENT" -c "$COOKIE_JAR" -b "$COOKIE_JAR" https://wbs-rewe.conn4.com/de/roaming/return/ | tee -a "$LOG_FILE"

echo "Checking internet connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Login Successful!" && exit 0 || { echo "Login failed or no internet access."; exit 1; }