#!/bin/bash
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

echo "Fetching initial portal page to get headers/cookies..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -v -A "$USER_AGENT" -c /tmp/c.txt -b /tmp/c.txt "https://canda-de.conn4.com/" 2>&1)
echo "HTTP Response captured." | tee -a "$LOG_FILE"

echo "Extracting grant_url from HTML..." | tee -a "$LOG_FILE"
GRANT_URL=$(echo "$RESPONSE" | grep -o '"grant_url":"[^"]*"' | sed 's/"grant_url":"//;s/"//g' | sed 's/\\\/\//\//g')

if [ -z "$GRANT_URL" ]; then
    echo "Error: Could not extract grant_url. Attempting direct grant request..." | tee -a "$LOG_FILE"
    # Fallback to standard Meraki grant structure if variable missing
    GRANT_URL="https://eu.network-auth.com/splash/LWndMchg.0.739/grant"
fi

echo "Submitting POST to grant URL: $GRANT_URL" | tee -a "$LOG_FILE"
# Meraki splash pages typically require a simple GET or empty POST to the grant_url to authorize
AUTH_RESPONSE=$(curl -v -A "$USER_AGENT" -c /tmp/c.txt -b /tmp/c.txt -X POST "$GRANT_URL" 2>&1)

echo "Checking connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "SUCCESS: Connected to Internet." | tee -a "$LOG_FILE" && exit 0 || { echo "FAILURE: Connectivity check failed."; exit 1; }