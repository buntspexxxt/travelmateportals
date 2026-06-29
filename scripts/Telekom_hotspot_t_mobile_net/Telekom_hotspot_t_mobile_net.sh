#!/bin/bash
LOG_FILE="/tmp/hotspot_login.log"
COOKIE_JAR="/tmp/telekom_cookies.txt"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "$(date): Starting multi-stage Telekom login script..." | tee -a "$LOG_FILE"

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

# 2. Initial connection and cookie setup
echo "Connecting to portal..." | tee -a "$LOG_FILE"
curl -v -L -k -c "$COOKIE_JAR" -b "$COOKIE_JAR" -A "$USER_AGENT" "http://detectportal.firefox.com/success.txt" -o /dev/null

# 3. Submit Free Login (ECOM3 API)
echo "Submitting ECOM3 FreeLogin request..." | tee -a "$LOG_FILE"
# Based on the provided JS configuration, the portal uses this endpoint to authenticate without payment
RESPONSE=$(curl -v -X POST "https://hotspot.t-mobile.net/wlan/rest/freeLogin" \
     -k -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
     -A "$USER_AGENT" \
     -H "Content-Type: application/x-www-form-urlencoded" \
     -H "Referer: https://hotspot.t-mobile.net/" \
     --data "rememberMe=true" 2>&1)

echo "Response: $RESPONSE" | tee -a "$LOG_FILE"

# 4. Connectivity verification
echo "Performing final connectivity check..." | tee -a "$LOG_FILE"
if ping -c 3 8.8.8.8 >/dev/null 2>&1; then
    echo "Success: Internet active." | tee -a "$LOG_FILE"
    exit 0
else
    echo "Error: Internet not active. Portal might require manual interaction in a browser." | tee -a "$LOG_FILE"
    exit 1
fi