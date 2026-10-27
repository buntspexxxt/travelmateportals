#!/bin/sh
# SCRIPT_VERSION="1.0.0"

LOG_FILE="/tmp/telekom_login.log"
trap 'rm -f "$COOKIE_FILE" "$HTML_OUT"' EXIT
COOKIE_FILE=$(mktemp)
HTML_OUT=$(mktemp)
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Waiting for IP, Gateway, and DNS..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 20 ]; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network and DNS are ready!" | tee -a "$LOG_FILE"
        sleep 2
        break
    fi
    sleep 1
    i=$((i + 1))
done

echo "Fetching redirect to identify portal..." | tee -a "$LOG_FILE"
REDIRECT_URL=$(curl -k -L -A "$UA" -c "$COOKIE_FILE" -w "%\{url_effective\}" -o "$HTML_OUT" -m 15 "http://neverssl.com")
REDIRECT_URL=$(echo "$REDIRECT_URL" | tr -d '\015')
echo "Effective URL: $REDIRECT_URL" | tee -a "$LOG_FILE"

echo "Submitting Free Login request..." | tee -a "$LOG_FILE"
# Based on T-Mobile Ecom3 architecture, the login endpoint typically expects a POST to the rest API
# Note: This portal is an Angular PWA, simple POSTing might be subject to XSRF protections if not handled correctly
# We attempt the standardized free login path identified in reference documentation
RESPONSE=$(curl -k -A "$UA" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -L -v \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "button=Login" \
    --data-urlencode "FNAME=0" \
    --data-urlencode "OriginatingServer=$REDIRECT_URL" \
    "https://hotspot.t-mobile.net/wlan/rest/freeLogin" 2>&1)

echo "HTTP Response: $RESPONSE" | tee -a "$LOG_FILE"

echo "Verifying real Internet connectivity (polling for up to 40 seconds)..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%\{http_code\}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
    if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
        echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
        exit 0
    fi
    echo "Attempt $i: Not connected yet (HTTP Check Code: $CHECK_CODE). Waiting..." | tee -a "$LOG_FILE"
    sleep 4
    i=$((i + 1))
done
echo "ERROR: Portal request completed but no Internet connectivity established after 40 seconds." | tee -a "$LOG_FILE"
exit 1