#!/bin/sh
# SCRIPT_VERSION="1.0.0"

LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE=$(mktemp)
HTML_FILE=$(mktemp)
trap 'rm -f "$COOKIE_FILE" "$HTML_FILE"' EXIT

echo "Starting Telekom Hotspot multi-step login..." | tee -a "$LOG_FILE"

# Wait for network
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

# 1. Capture initial session and XML
echo "Probing for login URL..." | tee -a "$LOG_FILE"
curl -m 15 -k -c "$COOKIE_FILE" -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -o "$HTML_FILE" "http://neverssl.com"

# 2. Extract Login URL
LOGIN_URL=$(cat "$HTML_FILE" | tr -d '\015' | sed -n 's/.*<loginurl>\([^<]*\)<\/loginurl>.*/\1/p' | sed 's/&amp;/\&/g')

if [ -z "$LOGIN_URL" ]; then
    echo "ERROR: Could not extract login URL." | tee -a "$LOG_FILE"
    exit 1
fi

# 3. Step 1: Free Login Request
echo "Submitting initial free login..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -m 15 -k -b "$COOKIE_FILE" -c "$COOKIE_FILE" -d "UserName=&Password=&FNAME=0&button=Login&OriginatingServer=http%3A%2F%2Fneverssl.com" "$LOGIN_URL")
echo "Response: $RESPONSE" | tee -a "$LOG_FILE"

# 4. Step 2: Handle modern ECOM3 Portal (JS context initialization)
# The HTML indicates an Angular app that requires session storage/cookies initialization.
echo "Initializing ECOM3 session context..." | tee -a "$LOG_FILE"
curl -m 15 -k -b "$COOKIE_FILE" -c "$COOKIE_FILE" -X GET "https://hotspot.t-mobile.net/wlan/rest/login/session"

# 5. Connectivity Check
echo "Verifying real Internet connectivity (polling for up to 40 seconds)..."
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
    if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
        echo "SUCCESS: Internet connection verified!"
        exit 0
    fi
    echo "Attempt $i: Not connected yet (HTTP Code: $CHECK_CODE). Waiting..."
    sleep 4
    i=$((i + 1))
done
exit 1