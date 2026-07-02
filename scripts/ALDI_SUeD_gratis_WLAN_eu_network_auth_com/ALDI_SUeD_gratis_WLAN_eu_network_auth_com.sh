#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Starting ALDI WiFi Login Script..." | tee -a "$LOG_FILE"

echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

echo "Detecting captive portal redirect..." | tee -a "$LOG_FILE"
# Extracting the initial portal redirect URL by querying a known non-HTTPS site
REDIRECT_RESPONSE=$(curl -v -A "$USER_AGENT" -o /dev/null --stderr - http://detectportal.firefox.com/success.txt)
LANDING_URL=$(echo "$REDIRECT_RESPONSE" | sed -n 's/.*Location: //p' | tr -d '\r')

if [ -z "$LANDING_URL" ]; then
    echo "Failed to detect redirect URL." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Found Redirect: $LANDING_URL" | tee -a "$LOG_FILE"

echo "Extracting base path for grant request..." | tee -a "$LOG_FILE"
# The portal logic uses a HEAD request to get the 'Continue-Url' header
# Extracting the base part of the URL up to the portal ID
BASE_URL=$(echo "$LANDING_URL" | sed 's/\/\?.*//')

echo "Requesting grant authorization via HEAD request..." | tee -a "$LOG_FILE"
RESPONSE_HEADERS=$(curl -v -I -X HEAD -A "$USER_AGENT" -H "X-Requested-With: XMLHttpRequest" "$LANDING_URL" 2>&1)
echo "Response Headers: $RESPONSE_HEADERS" | tee -a "$LOG_FILE"

CONTINUE_URL=$(echo "$RESPONSE_HEADERS" | sed -n 's/.*Continue-Url: //p' | tr -d '\r')

if [ -z "$CONTINUE_URL" ]; then
    echo "Failed to extract Continue-Url header. Portal might be down or already authenticated." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Submitting grant request to: $BASE_URL/grant?continue_url=$CONTINUE_URL" | tee -a "$LOG_FILE"
GRANT_URL="$BASE_URL/grant?continue_url=$CONTINUE_URL"

RESULT=$(curl -v -A "$USER_AGENT" "$GRANT_URL")
echo "Login submission response: $RESULT" | tee -a "$LOG_FILE"

sleep 5

echo "Checking internet connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Connectivity confirmed. Success." || (echo "Connectivity check failed." && exit 1)