#!/bin/bash
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/wifi_login.log"
echo "Starting login process..." | tee -a "$LOG_FILE"

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

COOKIE_FILE="/tmp/c.txt"
LANDING_FILE="/tmp/landing.html"

echo "Following portal redirect chain starting from NeverSSL..." | tee -a "$LOG_FILE"
FINAL_URL=$(curl -s -L -k -A "$USER_AGENT" -c "$COOKIE_FILE" -b "$COOKIE_FILE" -o "$LANDING_FILE" -w "%{url_effective}" "http://neverssl.com")
echo "Ended up at: $FINAL_URL" | tee -a "$LOG_FILE"

echo "Extracting grant_url from landing page..." | tee -a "$LOG_FILE"
GRANT_URL=$(grep -o '"grant_url":"[^"]*"' "$LANDING_FILE" | head -n 1 | sed 's/"grant_url":"//;s/"//g' | sed 's/\\\/\//\//g')

if [ -z "$GRANT_URL" ]; then
    echo "Error: Could not extract grant_url. Trying fallback URL..." | tee -a "$LOG_FILE"
    GRANT_URL="https://eu.network-auth.com/splash/LWndMchg.0.739/grant"
fi

echo "Submitting authorization POST to: $GRANT_URL" | tee -a "$LOG_FILE"
curl -s -k -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -X POST "$GRANT_URL" > /dev/null

echo "Checking connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "SUCCESS: Connected to Internet." | tee -a "$LOG_FILE" && exit 0 || { echo "FAILURE: Connectivity check failed."; exit 1; }