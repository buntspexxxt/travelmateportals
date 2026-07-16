#!/bin/sh
# SCRIPT_VERSION="1.0.0"

LOG_FILE="/tmp/portal_login.log"
COOKIE_FILE=$(mktemp)
HTML_FILE=$(mktemp)
trap 'rm -f "$COOKIE_FILE" "$HTML_FILE"' EXIT

echo "Starting Telekom Hotspot multi-step login..." | tee -a "$LOG_FILE"

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

echo "Capturing redirect details..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -k -L -w "%{url_effective}" -o "$HTML_FILE" -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" "http://neverssl.com")

LOGIN_URL=$(cat "$HTML_FILE" | tr -d '\015' | sed -n 's/.*<loginurl>\([^<]*\)<\/loginurl>.*/\1/p' | sed 's/&amp;/\&/g')

if [ -z "$LOGIN_URL" ]; then
    echo "ERROR: Could not extract login URL from portal HTML." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Submitting initial free login..." | tee -a "$LOG_FILE"
curl -v -k -m 15 -b "$COOKIE_FILE" -c "$COOKIE_FILE" -A "Mozilla/5.0" --data-urlencode "UserName=" --data-urlencode "Password=" --data-urlencode "FNAME=0" --data-urlencode "button=Login" --data-urlencode "OriginatingServer=http://neverssl.com" "$LOGIN_URL"

echo "Initializing ECOM3 session..." | tee -a "$LOG_FILE"
curl -v -k -m 15 -b "$COOKIE_FILE" -c "$COOKIE_FILE" -A "Mozilla/5.0" "https://hotspot.t-mobile.net/wlan/rest/login/session"

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

echo "ERROR: Portal request completed but no Internet connectivity established after 40 seconds." | tee -a "$LOG_FILE"
exit 1