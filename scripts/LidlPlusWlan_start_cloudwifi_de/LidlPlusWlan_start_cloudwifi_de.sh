#!/bin/bash
# SCRIPT_VERSION="1.0.0"

LOG_FILE="/tmp/wifi_login.log"
COOKIE_FILE="/tmp/wifi_cookies.txt"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

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

echo "Fetching captive portal redirect URL..." | tee -a "$LOG_FILE"
EFFECTIVE_URL=$(curl -k -L -A "$USER_AGENT" -c "$COOKIE_FILE" -w "%{url_effective}" -o /dev/null -m 15 "http://neverssl.com")
echo "Initial URL: $EFFECTIVE_URL" | tee -a "$LOG_FILE"

echo "Downloading portal page..." | tee -a "$LOG_FILE"
HTML=$(curl -k -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -m 15 "$EFFECTIVE_URL")

echo "Extracting hidden form fields..." | tee -a "$LOG_FILE"
NASID=$(echo "$HTML" | sed -n 's/.*name="nasid" value="\([^"]*\)".*/\1/p' | head -n 1)
MAC=$(echo "$HTML" | sed -n 's/.*name="mac" value="\([^"]*\)".*/\1/p' | head -n 1)
CHALLENGE=$(echo "$HTML" | sed -n 's/.*name="challenge" value="\([^"]*\)".*/\1/p' | head -n 1)
SESSIONID=$(echo "$HTML" | sed -n 's/.*name="sessionid" value="\([^"]*\)".*/\1/p' | head -n 1)
UAMIP=$(echo "$HTML" | sed -n 's/.*name="uamip" value="\([^"]*\)".*/\1/p' | head -n 1)
UAMPORT=$(echo "$HTML" | sed -n 's/.*name="uamport" value="\([^"]*\)".*/\1/p' | head -n 1)
CALLED=$(echo "$HTML" | sed -n 's/.*name="called" value="\([^"]*\)".*/\1/p' | head -n 1)
USERURL=$(echo "$HTML" | sed -n 's/.*name="userurl" value="\([^"]*\)".*/\1/p' | head -n 1)
TEMPLATE=$(echo "$HTML" | sed -n 's/.*name="FX_loginTemplate" value="\([^"]*\)".*/\1/p' | head -n 1)
DEVICEID=$(echo "$HTML" | sed -n 's/.*name="FX_hotspotDeviceId" value="\([^"]*\)".*/\1/p' | head -n 1)
USERNAME=$(echo "$HTML" | sed -n 's/.*name="FX_username" value="\([^"]*\)".*/\1/p' | head -n 1)

echo "Submitting 'Easy Login' POST request..." | tee -a "$LOG_FILE"
POST_DATA="cbQpC=1&nasid=$NASID&mac=$MAC&challenge=$CHALLENGE&uamip=$UAMIP&uamport=$UAMPORT&called=$CALLED&userurl=$USERURL&sessionid=$SESSIONID&FX_username=$USERNAME&FX_password=easy&FX_loginTemplate=$TEMPLATE&FX_loginType=Easy+Login&FX_hotspotDeviceId=$DEVICEID"

LOGIN_RESPONSE=$(curl -k -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -d "$POST_DATA" -m 15 -L "$EFFECTIVE_URL")
echo "Portal login complete." | tee -a "$LOG_FILE"

echo "Verifying real Internet connectivity..."
CHECK_CODE=$(curl -k -o /dev/null -w "%{http_code}" -m 8 "http://connectivitycheck.gstatic.com/generate_204")
if [ "$CHECK_CODE" = "204" ] || [ "$CHECK_CODE" = "200" ]; then
    echo "SUCCESS: Internet connection verified!"
    exit 0
else
    echo "ERROR: Portal request completed but no Internet connectivity established (HTTP Check Code: $CHECK_CODE)"
    exit 1
fi