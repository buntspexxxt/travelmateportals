#!/bin/bash

LOG_FILE="/tmp/wifi_login.log"
echo "Starting ALDI WLAN login process..." | tee -a "$LOG_FILE"

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

echo "Fetching redirect URL from captive portal..." | tee -a "$LOG_FILE"
# Get the initial redirect to capture dynamic parameters
RESPONSE=$(curl -v -A "$USER_AGENT" -L "http://detectportal.firefox.com/success.txt" 2>&1)
REDIRECT_URL=$(echo "$RESPONSE" | grep -i "Location:" | tail -n 1 | sed -n 's/.*Location: //p' | tr -d '\r')

if [ -z "$REDIRECT_URL" ]; then
    echo "Failed to find redirect URL. Manual intervention might be needed." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Extracted URL: $REDIRECT_URL" | tee -a "$LOG_FILE"

echo "Extracting base path and query parameters..." | tee -a "$LOG_FILE"
BASE_URL=$(echo "$REDIRECT_URL" | cut -d'?' -f1)
QUERY_PARAMS=$(echo "$REDIRECT_URL" | cut -d'?' -f2)

echo "Performing HEAD request to capture Continue-Url header..." | tee -a "$LOG_FILE"
# The portal logic uses a HEAD request to an API endpoint to finalize parameters
CONTINUE_HEADER=$(curl -v -I -A "$USER_AGENT" -X HEAD "$BASE_URL" --data "$QUERY_PARAMS" 2>&1 | grep -i "Continue-Url:" | awk '{print $2}' | tr -d '\r')

echo "Continue-Url header captured: $CONTINUE_HEADER" | tee -a "$LOG_FILE"

echo "Submitting final grant request..." | tee -a "$LOG_FILE"
# Grant endpoint format is /grant?continue_url=
GRANT_URL="$(echo "$BASE_URL" | sed 's/\/login/\/grant/')"
curl -v -A "$USER_AGENT" "$GRANT_URL?continue_url=$CONTINUE_HEADER" 2>&1 | tee -a "$LOG_FILE"

echo "Running connectivity check..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Success: Internet access confirmed." | tee -a "$LOG_FILE" && exit 0 || exit 1