#!/bin/bash
LOG_FILE="/tmp/wifi_login.log"
echo "Starting multi-stage login script for ALDI SÜD..." | tee -a "$LOG_FILE"

echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"; sleep 6; break; fi
    sleep 1
done

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE="/tmp/portal_cookies.txt"

echo "Stage 1: Fetching initial redirect and session parameters" | tee -a "$LOG_FILE"
REDIRECT_URL=$(curl -v -L -A "$USER_AGENT" -c "$COOKIE_FILE" -o /dev/null -w "%{url_effective}" http://detectportal.firefox.com/success.txt 2>&1 | grep "Location:" | tail -n1 | awk '{print $2}' | tr -d '\r')

if [ -z "$REDIRECT_URL" ]; then
    echo "Failed to find initial redirect URL. Already connected?" | tee -a "$LOG_FILE"
    exit 0
fi

BASE_URL=$(echo "$REDIRECT_URL" | cut -d'?' -f1)
echo "Base Portal URL: $BASE_URL" | tee -a "$LOG_FILE"

echo "Stage 2: Fetching Continue-Url via HEAD request" | tee -a "$LOG_FILE"
CONTINUE_HEADER_RESPONSE=$(curl -v -I -A "$USER_AGENT" -b "$COOKIE_FILE" -H "X-Requested-With: XMLHttpRequest" "$BASE_URL" 2>&1)
CONTINUE_URL=$(echo "$CONTINUE_HEADER_RESPONSE" | grep -i "Continue-Url:" | awk '{print $2}' | tr -d '\r')

if [ -z "$CONTINUE_URL" ]; then
    echo "Failed to extract Continue-Url from headers." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Extracted Continue-Url: $CONTINUE_URL" | tee -a "$LOG_FILE"

echo "Stage 3: Submitting final grant request" | tee -a "$LOG_FILE"
GRANT_URL="${BASE_URL}grant?continue_url=$(echo -n "$CONTINUE_URL" | python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read()))")"

RESPONSE=$(curl -v -L -A "$USER_AGENT" -b "$COOKIE_FILE" "$GRANT_URL" 2>&1)
echo "HTTP Final Response Code: $?" | tee -a "$LOG_FILE"

echo "Connectivity check..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Success: Connected." | tee -a "$LOG_FILE" && exit 0 || exit 1