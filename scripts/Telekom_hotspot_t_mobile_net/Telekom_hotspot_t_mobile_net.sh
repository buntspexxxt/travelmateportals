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

# 2. Initial Redirect & Cookie Capture
echo "Initial connection attempt..." | tee -a "$LOG_FILE"
RESPONSE_CODE=$(curl -v -L -k -c "$COOKIE_JAR" -b "$COOKIE_JAR" -A "$USER_AGENT" "http://detectportal.firefox.com/success.txt" -o /dev/null -w "%{http_code}")
echo "HTTP Response: $RESPONSE_CODE" | tee -a "$LOG_FILE"

# 3. Extract path components and submit freeLogin
echo "Submitting freeLogin payload..." | tee -a "$LOG_FILE"
# The portal uses an Angular app (ECOM3) that POSTs to wlan/rest/freeLogin
# We maintain the session cookie from the initial connection
POST_RESPONSE=$(curl -v -X POST "https://hotspot.t-mobile.net/wlan/rest/freeLogin" \
     -k -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
     -A "$USER_AGENT" \
     -H "Content-Type: application/x-www-form-urlencoded" \
     -H "Referer: https://hotspot.t-mobile.net/" \
     --data "rememberMe=true" 2>&1)

echo "POST Response: $POST_RESPONSE" | tee -a "$LOG_FILE"

# 4. Verification Check
echo "Verifying connectivity..." | tee -a "$LOG_FILE"
if ping -c 3 8.8.8.8 >/dev/null 2>&1; then
    echo "Success: Internet active." | tee -a "$LOG_FILE"
    exit 0
else
    echo "Warning: Ping failed, but maybe portal session is established. Check browser if needed." | tee -a "$LOG_FILE"
    exit 1
fi