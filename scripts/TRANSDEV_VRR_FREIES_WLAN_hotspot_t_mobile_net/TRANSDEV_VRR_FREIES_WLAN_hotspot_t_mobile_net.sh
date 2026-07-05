#!/bin/bash

trap 'rm -f "${COOKIE_JAR:-}"' EXIT
LOG_FILE="/tmp/portal_login.log"
COOKIE_JAR="/tmp/telekom_cookies.txt"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Starting refined login for Transdev VRR..." | tee -a "$LOG_FILE"

# 1. Wait for DHCP
echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
done

# 2. Session Init
rm -f "$COOKIE_JAR"
echo "Initializing session..." | tee -a "$LOG_FILE"
curl -k -A "$USER_AGENT" -c "$COOKIE_JAR" -b "$COOKIE_JAR" "http://neverssl.com" > /dev/null 2>&1

# 3. Handle ECOM3 stateful transition (Free Login)
echo "Submitting ECOM3 free login request..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
     -X POST "https://hotspot.t-mobile.net/wlan/rest/freeLogin" \
     -H "Content-Type: application/x-www-form-urlencoded" \
     -d "button=Login&UserName=&Password=&FNAME=0")
echo "HTTP Response: $RESPONSE" | tee -a "$LOG_FILE"

# 4. Final activation payload for ECOM3
echo "Submitting final JSON activation..." | tee -a "$LOG_FILE"
curl -k -v -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
     -X POST "https://hotspot.t-mobile.net/wlan/rest/freeLogin" \
     -H "Content-Type: application/json" \
     -d '{"rememberMe":true}' | tee -a "$LOG_FILE"

# 5. Final Connectivity Check
echo "Verifying real Internet connectivity..." | tee -a "$LOG_FILE"
CHECK_CODE=$(curl -k -s -o /dev/null -w "%\{http_code\}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    exit 1
fi