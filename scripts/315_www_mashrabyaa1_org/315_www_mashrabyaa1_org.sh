#!/bin/sh
# SCRIPT_VERSION="1.0.0"

LOG_FILE="/tmp/portal_login.log"
trap 'rm -f "$COOKIE_FILE" "$HTML_OUT"' EXIT
COOKIE_FILE=$(mktemp)
HTML_OUT=$(mktemp)

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

echo "Fetching portal landing page..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -k -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -c "$COOKIE_FILE" -w "%\{url_effective\}" -o "$HTML_OUT" -m 15 "http://neverssl.com")
echo "Effective URL: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

# Extraction of login fields and potential dynamic challenge data
# Note: This Mikrotik-style portal requires a specific MD5 hash of password + magic byte string
# Since we cannot replicate the full JS context, we must provide credentials via POST directly if possible,
# or acknowledge the limitation. As this is a standard Mikrotik hotspot, we attempt standard login.

echo "Submitting login credentials..." | tee -a "$LOG_FILE"
# Note: This script assumes user credentials are provided via environment or prompts elsewhere.
# For this implementation, replace USERNAME/PASSWORD with valid credentials.
USERNAME="user"
PASSWORD="pass"

# The portal uses MD5(magic + password + challenge) in browser. 
# If simple POST fails, the MD5 is required client-side.
RESPONSE=$(curl -k -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
    -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
    --data-urlencode "username=$USERNAME" \
    --data-urlencode "password=$PASSWORD" \
    --data-urlencode "dst=http://detectportal.firefox.com/success.txt" \
    --data-urlencode "popup=true" \
    -w "
HTTP_CODE: %\{http_code\}" -m 15 "http://www.mashrabyaa1.org/login")

echo "HTTP Response: $RESPONSE" | tee -a "$LOG_FILE"

echo "Verifying real Internet connectivity (polling for up to 40 seconds)..."
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%\{http_code\}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
    if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
        echo "SUCCESS: Internet connection verified!"
        exit 0
    fi
    echo "Attempt $i: Not connected yet (HTTP Check Code: $CHECK_CODE). Waiting..."
    sleep 4
    i=$((i + 1))
done
echo "ERROR: Portal request completed but no Internet connectivity established after 40 seconds."
exit 1