#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE="/tmp/cookies.txt"

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
REDIRECT_RESPONSE=$(curl -v -A "$USER_AGENT" -c "$COOKIE_FILE" -o /dev/null --stderr - http://detectportal.firefox.com/success.txt)
LANDING_URL=$(echo "$REDIRECT_RESPONSE" | sed -n 's/.*Location: //p' | tr -d '\r')

if [ -z "$LANDING_URL" ]; then
    echo "Failed to detect redirect URL." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Found Redirect: $LANDING_URL" | tee -a "$LOG_FILE"
BASE_URL=$(echo "$LANDING_URL" | sed 's/\/\?.*//')

echo "Requesting initial splash page..." | tee -a "$LOG_FILE"
curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -o /dev/null "$LANDING_URL" | tee -a "$LOG_FILE"

echo "Requesting grant authorization via HEAD request..." | tee -a "$LOG_FILE"
RESPONSE_HEADERS=$(curl -v -I -X HEAD -A "$USER_AGENT" -b "$COOKIE_FILE" -H "X-Requested-With: XMLHttpRequest" "$LANDING_URL" 2>&1)
CONTINUE_URL=$(echo "$RESPONSE_HEADERS" | sed -n 's/.*Continue-Url: //p' | tr -d '\r')

if [ -z "$CONTINUE_URL" ]; then
    echo "Failed to extract Continue-Url. Assuming already authenticated or session active." | tee -a "$LOG_FILE"
else
    GRANT_URL="$BASE_URL/grant?continue_url=$CONTINUE_URL"
    echo "Submitting grant request to: $GRANT_URL" | tee -a "$LOG_FILE"
    RESULT=$(curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" "$GRANT_URL")
    echo "Login submission response: $RESULT" | tee -a "$LOG_FILE"
fi

sleep 5

echo "Checking internet connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Connectivity confirmed. Success." || (echo "Connectivity check failed." && exit 1)