#!/bin/bash

LOG_FILE="/tmp/wifi_login.log"
COOKIE_FILE="/tmp/wifi_cookies.txt"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

echo "Fetching captive portal redirect URL..." | tee -a "$LOG_FILE"
REDIRECT_RESPONSE=$(curl -v -A "$USER_AGENT" -L -c "$COOKIE_FILE" "http://neverssl.com" 2>&1)

# Extract the effective URL from curl stderr
REDIRECT_URL=$(echo "$REDIRECT_RESPONSE" | sed -n 's/.*Location: //p' | tr -d '\r' | tail -n 1)
if [ -z "$REDIRECT_URL" ]; then
    REDIRECT_URL="https://start.cloudwifi.de/"
    echo "Could not extract redirect, using default: $REDIRECT_URL" | tee -a "$LOG_FILE"
else
    echo "Redirect URL: $REDIRECT_URL" | tee -a "$LOG_FILE"
fi

echo "Downloading portal page to extract form fields..." | tee -a "$LOG_FILE"
HTML=$(curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$REDIRECT_URL")

echo "Extracting dynamic form inputs..." | tee -a "$LOG_FILE"
# Using sed to extract values from hidden inputs
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

echo "Submitting login form..." | tee -a "$LOG_FILE"
LOGIN_RESPONSE=$(curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -d "cbQpC=1&nasid=$NASID&mac=$MAC&challenge=$CHALLENGE&uamip=$UAMIP&uamport=$UAMPORT&called=$CALLED&userurl=$USERURL&sessionid=$SESSIONID&FX_username=$USERNAME&FX_password=easy&FX_loginTemplate=$TEMPLATE&FX_loginType=Easy+Login&FX_hotspotDeviceId=$DEVICEID" -X POST "$REDIRECT_URL" 2>&1)

echo "HTTP Response Summary: $(echo "$LOGIN_RESPONSE" | grep "HTTP/" | tail -n 1)" | tee -a "$LOG_FILE"

echo "Verifying connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Success: Connected to internet." | tee -a "$LOG_FILE" || { echo "Error: No internet detected." | tee -a "$LOG_FILE"; exit 1; }