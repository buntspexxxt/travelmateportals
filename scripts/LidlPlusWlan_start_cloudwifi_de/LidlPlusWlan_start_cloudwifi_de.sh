#!/bin/sh
# SCRIPT_VERSION="1.1.0"

LOG_FILE="/tmp/wifi_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE=$(mktemp)
trap 'rm -f "$COOKIE_FILE"' EXIT

echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 20 ]; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
    i=$((i + 1))
done

echo "Fetching captive portal redirect URL..." | tee -a "$LOG_FILE"
REDIRECT_RESPONSE=$(curl -m 15 -k -v -A "$USER_AGENT" -L -c "$COOKIE_FILE" "http://neverssl.com" 2>&1)

# Extract the effective URL from curl Location headers
REDIRECT_URL=$(echo "$REDIRECT_RESPONSE" | sed -n 's/.*Location: //p' | tr -d '\r' | tail -n 1)
if [ -z "$REDIRECT_URL" ]; then
    REDIRECT_URL="https://start.cloudwifi.de/"
    echo "Could not extract redirect, using default: $REDIRECT_URL" | tee -a "$LOG_FILE"
else
    echo "Redirect URL: $REDIRECT_URL" | tee -a "$LOG_FILE"
fi

echo "Downloading portal page to extract form fields..." | tee -a "$LOG_FILE"
HTML=$(curl -m 15 -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$REDIRECT_URL")

echo "Extracting dynamic form inputs..." | tee -a "$LOG_FILE"
decode_html() {
    echo "$1" | sed -e 's/\&amp;/\&/g' -e 's/\&#x3D;/=/g' -e 's/\&quot;/"/g' -e 's/\&apos;/'\''/g' -e 's/\&lt;/</g' -e 's/\&gt;/>/g'
}

NASID=$(decode_html "$(echo "$HTML" | sed -n 's/.*name="nasid" value="\([^"]*\)".*/\1/p' | head -n 1)")
MAC=$(decode_html "$(echo "$HTML" | sed -n 's/.*name="mac" value="\([^"]*\)".*/\1/p' | head -n 1)")
CHALLENGE=$(decode_html "$(echo "$HTML" | sed -n 's/.*name="challenge" value="\([^"]*\)".*/\1/p' | head -n 1)")
SESSIONID=$(decode_html "$(echo "$HTML" | sed -n 's/.*name="sessionid" value="\([^"]*\)".*/\1/p' | head -n 1)")
UAMIP=$(decode_html "$(echo "$HTML" | sed -n 's/.*name="uamip" value="\([^"]*\)".*/\1/p' | head -n 1)")
UAMPORT=$(decode_html "$(echo "$HTML" | sed -n 's/.*name="uamport" value="\([^"]*\)".*/\1/p' | head -n 1)")
CALLED=$(decode_html "$(echo "$HTML" | sed -n 's/.*name="called" value="\([^"]*\)".*/\1/p' | head -n 1)")
USERURL=$(decode_html "$(echo "$HTML" | sed -n 's/.*name="userurl" value="\([^"]*\)".*/\1/p' | head -n 1)")
TEMPLATE=$(decode_html "$(echo "$HTML" | sed -n 's/.*name="FX_loginTemplate" value="\([^"]*\)".*/\1/p' | head -n 1)")
DEVICEID=$(decode_html "$(echo "$HTML" | sed -n 's/.*name="FX_hotspotDeviceId" value="\([^"]*\)".*/\1/p' | head -n 1)")
USERNAME=$(decode_html "$(echo "$HTML" | sed -n 's/.*name="FX_username" value="\([^"]*\)".*/\1/p' | head -n 1)")

echo "Submitting login form..." | tee -a "$LOG_FILE"
LOGIN_RESPONSE=$(curl -m 15 -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
  --data-urlencode "cbQpC=1" \
  --data-urlencode "nasid=$NASID" \
  --data-urlencode "mac=$MAC" \
  --data-urlencode "challenge=$CHALLENGE" \
  --data-urlencode "uamip=$UAMIP" \
  --data-urlencode "uamport=$UAMPORT" \
  --data-urlencode "called=$CALLED" \
  --data-urlencode "userurl=$USERURL" \
  --data-urlencode "sessionid=$SESSIONID" \
  --data-urlencode "FX_username=$USERNAME" \
  --data-urlencode "FX_password=easy" \
  --data-urlencode "FX_loginTemplate=$TEMPLATE" \
  --data-urlencode "FX_loginType=Easy Login" \
  --data-urlencode "FX_hotspotDeviceId=$DEVICEID" \
  -X POST "$REDIRECT_URL" 2>&1)

echo "HTTP Response Summary: $(echo "$LOGIN_RESPONSE" | grep "HTTP/" | tail -n 1)" | tee -a "$LOG_FILE"

echo "Verifying connectivity..." | tee -a "$LOG_FILE"
CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!" | tee -a "$LOG_FILE"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)" | tee -a "$LOG_FILE"
    exit 1
fi