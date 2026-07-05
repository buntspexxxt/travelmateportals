#!/bin/bash

trap 'rm -f "${COOKIE_JAR:-}"' EXIT
LOG_FILE="/tmp/portal_login.log"
COOKIE_JAR="/tmp/telekom_cookies.txt"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Starting refined login for Transdev VRR..." | tee -a "$LOG_FILE"

echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
done

rm -f "$COOKIE_JAR"
echo "Initializing session and capturing landing URL from neverssl.com..." | tee -a "$LOG_FILE"
# Capture verbose output to find Location headers
INITIAL_CURL_OUTPUT=$(curl -k -v -A "$USER_AGENT" -c "$COOKIE_JAR" -b "$COOKIE_JAR" "http://neverssl.com" 2>&1)
echo "$INITIAL_CURL_OUTPUT" | tee -a "$LOG_FILE"

# Extract the last Location header from the verbose output
LANDING_URL=$(echo "$INITIAL_CURL_OUTPUT" | sed -n 's/^< Location: //p' | sed "s/\r//g" | tail -n 1)

if [ -z "$LANDING_URL" ]; then
    echo "ERROR: Could not find Landing URL in initial redirects. Aborting." | tee -a "$LOG_FILE"
    exit 1
fi
echo "Detected Landing URL: $LANDING_URL" | tee -a "$LOG_FILE"

# Visit the landing page to properly initialize the session and get any initial dynamic content/cookies
echo "Visiting the detected landing page to establish full session context: $LANDING_URL" | tee -a "$LOG_FILE"
LANDING_PAGE_GET_OUTPUT=$(curl -k -v -A "$USER_AGENT" -c "$COOKIE_JAR" -b "$COOKIE_JAR" "$LANDING_URL" 2>&1)
echo "$LANDING_PAGE_GET_OUTPUT" | tee -a "$LOG_FILE"
if echo "$LANDING_PAGE_GET_OUTPUT" | grep -q "< HTTP/1.[01] [45][0-9][0-9]"; then
    echo "ERROR: Visiting landing page returned a client or server error. Aborting." | tee -a "$LOG_FILE"
    exit 1
fi
# The HTML content itself is not explicitly processed by this script, as the login might happen via the REST API.

echo "Performing initial handshake with /rest/init..." | tee -a "$LOG_FILE"
curl -k -v -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" -X GET "https://hotspot.t-mobile.net/wlan/rest/init" >> "$LOG_FILE" 2>&1
if [ $? -ne 0 ]; then
    echo "ERROR: Initial handshake /rest/init failed. Aborting." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Submitting ECOM3 free login request..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
     -X POST "https://hotspot.t-mobile.net/wlan/rest/freeLogin" \
     -H "Content-Type: application/x-www-form-urlencoded" \
     -d "button=Login&UserName=&Password=&FNAME=0" 2>&1)
echo "$RESPONSE" | tee -a "$LOG_FILE"
if echo "$RESPONSE" | grep -q "< HTTP/1.[01] [45][0-9][0-9]"; then
    echo "ERROR: ECOM3 free login request (form-urlencoded) failed. Aborting." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Submitting final JSON activation..." | tee -a "$LOG_FILE"
JSON_RESPONSE=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
     -X POST "https://hotspot.t-mobile.net/wlan/rest/freeLogin" \
     -H "Content-Type: application/json" \
     -d '{"rememberMe":true}' 2>&1)
echo "$JSON_RESPONSE" | tee -a "$LOG_FILE"
if echo "$JSON_RESPONSE" | grep -q "< HTTP/1.[01] [45][0-9][0-9]"; then
    echo "ERROR: Final JSON activation failed. Aborting." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Verifying real Internet connectivity..." | tee -a "$LOG_FILE"
CHECK_CODE=$(curl -k -s -o /dev/null -w "%\{http_code\}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    exit 1
fi
