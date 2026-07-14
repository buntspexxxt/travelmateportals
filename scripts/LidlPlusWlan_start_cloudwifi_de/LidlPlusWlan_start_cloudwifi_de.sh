#!/bin/sh
# SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/wifi_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE=$(mktemp)
trap 'rm -f "$COOKIE_FILE"' EXIT

echo "Waiting for network..." | tee -a "$LOG_FILE"
i=1
while [ $i -le 20 ]; do
    if ip route | grep -q default && nslookup neverssl.com >/dev/null 2>&1; then
        echo "Network ready." | tee -a "$LOG_FILE"
        break
    fi
    sleep 2
    i=$((i + 1))
done

echo "Fetching portal..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -k -L -A "$USER_AGENT" -w "%{url_effective}" -o /dev/null "http://neverssl.com" 2>/dev/null | tr -d '\015')
HTML=$(curl -k -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$EFFECTIVE_URL")

echo "Extracting form inputs..." | tee -a "$LOG_FILE"
decode_html() { echo "$1" | sed -e 's/\&amp;/\&/g' -e 's/\&#x3D;/=/g' -e 's/\&quot;/"/g'; }

# Extracting via POSIX compliant sed
NASID=$(echo "$HTML" | sed -n 's/.*name="nasid" value="\([^"]*\)".*/\1/p' | head -n 1 | tr -d '\015')
MAC=$(echo "$HTML" | sed -n 's/.*name="mac" value="\([^"]*\)".*/\1/p' | head -n 1 | tr -d '\015')
CHALLENGE=$(echo "$HTML" | sed -n 's/.*name="challenge" value="\([^"]*\)".*/\1/p' | head -n 1 | tr -d '\015')
SESSIONID=$(echo "$HTML" | sed -n 's/.*name="sessionid" value="\([^"]*\)".*/\1/p' | head -n 1 | tr -d '\015')
UAMIP=$(echo "$HTML" | sed -n 's/.*name="uamip" value="\([^"]*\)".*/\1/p' | head -n 1 | tr -d '\015')
UAMPORT=$(echo "$HTML" | sed -n 's/.*name="uamport" value="\([^"]*\)".*/\1/p' | head -n 1 | tr -d '\015')
CALLED=$(echo "$HTML" | sed -n 's/.*name="called" value="\([^"]*\)".*/\1/p' | head -n 1 | tr -d '\015')
USERURL=$(echo "$HTML" | sed -n 's/.*name="userurl" value="\([^"]*\)".*/\1/p' | head -n 1 | tr -d '\015')
TEMPLATE=$(echo "$HTML" | sed -n 's/.*name="FX_loginTemplate" value="\([^"]*\)".*/\1/p' | head -n 1 | tr -d '\015')
DEVICEID=$(echo "$HTML" | sed -n 's/.*name="FX_hotspotDeviceId" value="\([^"]*\)".*/\1/p' | head -n 1 | tr -d '\015')
USERNAME=$(decode_html "$(echo "$HTML" | sed -n 's/.*name="FX_username" value="\([^"]*\)".*/\1/p' | head -n 1 | tr -d '\015')")

echo "Submitting form..." | tee -a "$LOG_FILE"
curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
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
  -X POST "$EFFECTIVE_URL" >> "$LOG_FILE" 2>&1

echo "Verifying real Internet connectivity (polling for up to 40 seconds)..."
i=1
while [ $i -le 10 ]; do
    CHECK_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
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