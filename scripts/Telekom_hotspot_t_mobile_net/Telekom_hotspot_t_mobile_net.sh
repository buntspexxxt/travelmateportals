#!/bin/bash
LOG_FILE="/tmp/hotspot_login.log"
COOKIE_JAR="/tmp/telekom_cookies.txt"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "$(date): Starting multi-stage Telekom login script..." | tee -a "$LOG_FILE"

echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

echo "Fetching initial portal page to get cookies and session parameters..." | tee -a "$LOG_FILE"
curl -v -k -c "$COOKIE_JAR" -b "$COOKIE_JAR" -A "$USER_AGENT" "http://detectportal.firefox.com/success.txt" -o /dev/null

echo "Submitting ECOM3 FreeLogin request..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -v -X POST "https://hotspot.t-mobile.net/wlan/rest/freeLogin" \
     -k -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
     -A "$USER_AGENT" \
     -H "Content-Type: application/x-www-form-urlencoded" \
     --data "rememberMe=true" 2>&1)

echo "Login response: $RESPONSE" | tee -a "$LOG_FILE"

echo "Checking status and finalizing session..." | tee -a "$LOG_FILE"
STATUS_JSON=$(curl -v -k -b "$COOKIE_JAR" -A "$USER_AGENT" "https://hotspot.t-mobile.net/wlan/rest/status")
echo "Status JSON: $STATUS_JSON" | tee -a "$LOG_FILE"

echo "Performing connectivity check..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null 2>&1 && exit 0 || exit 1