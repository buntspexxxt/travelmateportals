#!/bin/bash

# Auto-injected cleanup trap for temporary session files
trap 'rm -f "${COOKIE_JAR:-}" "${COOKIE_FILE:-}" "${HTML_FILE:-}"' EXIT
LOG_FILE="/tmp/portal_login.log"
COOKIE_JAR="/tmp/telekom_cookies.txt"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Starting login script for Transdev VRR Telekom Hotspot..." | tee -a "$LOG_FILE"

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

# 2. Setup session
rm -f "$COOKIE_JAR"
echo "Initializing session with landing page..." | tee -a "$LOG_FILE"
curl -k -v -A "$USER_AGENT" -c "$COOKIE_JAR" -b "$COOKIE_JAR" "http://neverssl.com" > /dev/null 2>&1

# 3. Submit Free Login
echo "Submitting freeLogin activation via POST..." | tee -a "$LOG_FILE"
# The portal expects standard form-encoded free login for this specific T-Mobile variant
RESPONSE=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
     -X POST "https://hotspot.t-mobile.net/wlan/rest/freeLogin" \
     -H "Content-Type: application/x-www-form-urlencoded" \
     -d "button=Login&UserName=&Password=&FNAME=0" 2>&1)
echo "HTTP Response: $RESPONSE" | tee -a "$LOG_FILE"

# 4. Check for potential secondary acceptance (common in ECOM3 portals)
echo "Checking if terms agreement is required..." | tee -a "$LOG_FILE"
# If previous POST wasn't enough, we perform a JSON accept if required by ECOM3
curl -k -v -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
     -X POST "https://hotspot.t-mobile.net/wlan/rest/freeLogin" \
     -H "Content-Type: application/json" \
     -d '{"rememberMe":true}' > /dev/null 2>&1

# 5. Final Connectivity Check
echo "Verifying real Internet connectivity..." | tee -a "$LOG_FILE"
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    exit 1
fi