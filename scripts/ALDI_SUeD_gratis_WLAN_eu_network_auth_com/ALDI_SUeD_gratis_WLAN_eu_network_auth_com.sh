#!/bin/bash
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/portal_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE="/tmp/cookies.txt"

echo "Starting ALDI WiFi Login Script..." | tee -a "$LOG_FILE"

echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
done

echo "Detecting captive portal redirect..." | tee -a "$LOG_FILE"
REDIRECT_URL=$(curl -k -v -A "$USER_AGENT" -c "$COOKIE_FILE" -s -o /dev/null -w "%{redirect_url}" http://neverssl.com)

if [ -z "$REDIRECT_URL" ]; then
    echo "Failed to detect redirect, trying secondary check..." | tee -a "$LOG_FILE"
    REDIRECT_URL=$(curl -k -v -A "$USER_AGENT" -c "$COOKIE_FILE" -s -o /dev/null -w "%{redirect_url}" http://detectportal.firefox.com/success.txt)
fi

if [ -z "$REDIRECT_URL" ]; then
    echo "CRITICAL: Could not detect captive portal redirect URL." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Captive portal redirect detected: $REDIRECT_URL" | tee -a "$LOG_FILE"

BASE_URL=$(echo "$REDIRECT_URL" | cut -d'/' -f1-4)
echo "Dynamic Base URL: $BASE_URL" | tee -a "$LOG_FILE"

echo "Fetching main page to get cookies and state..." | tee -a "$LOG_FILE"
HTML=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$REDIRECT_URL")

echo "Extracting grant link from the page..." | tee -a "$LOG_FILE"
GRANT_PATH=$(echo "$HTML" | sed -n 's/.*<a class="button" href="\([^"]*\)".*/\1/p' | sed 's/&amp;/\&/g')

if [ -z "$GRANT_PATH" ]; then
    echo "Failed to extract grant link." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Executing Grant Request: $GRANT_PATH" | tee -a "$LOG_FILE"
GRANT_RESPONSE=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -H "Referer: $REDIRECT_URL" "$GRANT_PATH" 2>&1)

echo "Verifying real Internet connectivity..." | tee -a "$LOG_FILE"
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    exit 1
fi