#!/bin/bash

trap 'rm -f "\${COOKIE_JAR:-}"' EXIT
LOG_FILE="/tmp/portal_login.log"
COOKIE_JAR="/tmp/telekom_cookies.txt"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Starting refined login for Transdev VRR..." | tee -a "\$LOG_FILE"

# Wait loop for network readiness
echo "Waiting for IP, Gateway, and DNS..." | tee -a "\$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "\$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
done

# Initialize Session
echo "Capturing initial session..." | tee -a "\$LOG_FILE"
curl -k -v -A "\$USER_AGENT" -c "\$COOKIE_JAR" -b "\$COOKIE_JAR" "http://neverssl.com" > /dev/null 2>&1

# Submit initial free login request
echo "Submitting REST free login..." | tee -a "\$LOG_FILE"
RESPONSE=\$(curl -k -v -A "\$USER_AGENT" -b "\$COOKIE_JAR" -c "\$COOKIE_JAR" \
     -X POST "https://hotspot.t-mobile.net/wlan/rest/freeLogin" \
     -H "Content-Type: application/x-www-form-urlencoded" \
     -d "button=Login&UserName=&Password=&FNAME=0" 2>&1)
echo "HTTP Response Code: \$RESPONSE" | tee -a "\$LOG_FILE"

# Submit secondary session activation (ecom3 workflow)
echo "Activating session with rememberMe..." | tee -a "\$LOG_FILE"
JSON_RESPONSE=\$(curl -k -v -A "\$USER_AGENT" -b "\$COOKIE_JAR" -c "\$COOKIE_JAR" \
     -X POST "https://hotspot.t-mobile.net/wlan/rest/freeLogin" \
     -H "Content-Type: application/json" \
     -d '{"rememberMe":true}' 2>&1)
echo "HTTP Response: \$JSON_RESPONSE" | tee -a "\$LOG_FILE"

# Final Connectivity Check
echo "Verifying real Internet connectivity..." | tee -a "\$LOG_FILE"
CHECK_CODE=\$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "\$CHECK_CODE" = "204" ] || [ "\$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "\$LOG_FILE"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: \$CHECK_CODE)" | tee -a "\$LOG_FILE"
    exit 1
fi