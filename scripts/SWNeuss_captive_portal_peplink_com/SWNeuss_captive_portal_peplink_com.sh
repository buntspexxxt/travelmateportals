#!/bin/env bash

# Helper function to decode URL-encoded parameters in a portable way
urldecode() {
    echo "$1" | sed 's/%3A/:/g; s/%2F/\//g; s/%3F/?/g; s/%3D/=/g; s/%26/\&/g; s/%2C/,/g; s/%2B/+/g; s/%20/ /g; s/%40/@/g'
}

check_quota() {
    echo "=== Checking Quota ==="
    if [ -n "$RESUME_RESPONSE" ]; then
        echo "Session/Quota info: $RESUME_RESPONSE"
    else
        echo "No active session info available to query quota."
    fi
}

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Step 1: Attempting to trigger redirect and capture the effective landing page URL..."
REDIRECT_URL=$(curl -v -L -o /dev/null -w "%{url_effective}" -A "$USER_AGENT" "http://detectportal.firefox.com/success.txt")

echo "Captured Redirect URL: $REDIRECT_URL"

if [ -z "$REDIRECT_URL" ] || [ "$REDIRECT_URL" = "http://detectportal.firefox.com/success.txt" ]; then
    echo "No redirect detected or already connected. Verifying internet connectivity..."
    if ping -c 3 8.8.8.8 >/dev/null; then
        echo "SUCCESS: Already connected to the internet!"
        exit 0
    else
        echo "ERROR: Not connected, but failed to retrieve captive portal redirect URL."
        exit 1
    fi
fi

echo "Step 2: Extracting dynamic portal parameters from redirect URL..."
CHECKSUM=$(echo "$REDIRECT_URL" | grep -o 'checksum=[^&]*' | cut -d= -f2)
CP_ID=$(echo "$REDIRECT_URL" | grep -o 'cp_id=[^&]*' | cut -d= -f2)
TIME=$(echo "$REDIRECT_URL" | grep -o 'time=[^&]*' | cut -d= -f2)
IP=$(echo "$REDIRECT_URL" | grep -o 'ip=[^&]*' | cut -d= -f2)
CLIENT_MAC=$(echo "$REDIRECT_URL" | grep -o 'client_mac=[^&]*' | cut -d= -f2)
HOST_IP=$(echo "$REDIRECT_URL" | grep -o 'host_ip=[^&]*' | cut -d= -f2)
SSID=$(echo "$REDIRECT_URL" | grep -o 'ssid=[^&]*' | cut -d= -f2)
SN=$(echo "$REDIRECT_URL" | grep -o 'sn=[^&]*' | cut -d= -f2)
HOST_MAC=$(echo "$REDIRECT_URL" | grep -o 'host_mac=[^&]*' | cut -d= -f2)
ORIG_URL=$(echo "$REDIRECT_URL" | grep -o 'orig_url=[^&]*' | cut -d= -f2)

# URL-decode the extracted parameters to ensure proper structure
CLIENT_MAC=$(urldecode "$CLIENT_MAC")
SSID=$(urldecode "$SSID")
CP_ID=$(urldecode "$CP_ID")
ORIG_URL=$(urldecode "$ORIG_URL")

echo "Extracted Parameters:"
echo "  CHECKSUM: $CHECKSUM"
echo "  CP_ID: $CP_ID"
echo "  TIME: $TIME"
echo "  IP: $IP"
echo "  CLIENT_MAC: $CLIENT_MAC"
echo "  HOST_IP: $HOST_IP"
echo "  SSID: $SSID"
echo "  SN: $SN"
echo "  HOST_MAC: $HOST_MAC"
echo "  ORIG_URL: $ORIG_URL"

echo "Step 3: Fetching the captive portal landing page HTML to extract the Peplink InControl base domain..."
HTML_CONTENT=$(curl -v -c /tmp/cookies.txt -b /tmp/cookies.txt -A "$USER_AGENT" "$REDIRECT_URL")

BASE_PORTAL_URL=$(echo "$HTML_CONTENT" | grep -o 'https://[^/]*/cp/session/resume' | sed 's|/cp/session/resume||' | head -n 1)
if [ -z "$BASE_PORTAL_URL" ]; then
    echo "Warning: Could not dynamically extract InControl base domain. Falling back to default guest7.ic.peplink.com."
    BASE_PORTAL_URL="https://guest7.ic.peplink.com"
fi
echo "Using InControl Base Portal URL: $BASE_PORTAL_URL"

echo "Step 4: Making AJAX session resume request to get current session configuration..."
TIMESTAMP=$(date +%s)000
RESUME_RESPONSE=$(curl -v -c /tmp/cookies.txt -b /tmp/cookies.txt -A "$USER_AGENT" \
  "${BASE_PORTAL_URL}/cp/session/resume?client_mac=${CLIENT_MAC}&sn=${SN}&ssid=${SSID}&time=${TIME}&cp_id=${CP_ID}&checksum=${CHECKSUM}&_=${TIMESTAMP}")

echo "Resume Response payload: $RESUME_RESPONSE"
check_quota

echo "Step 5: Extracting session flags from resume response..."
ACCESS_MODE=$(echo "$RESUME_RESPONSE" | grep -o '"access_mode":"[^"]*"' | cut -d'"' -f4)
MARKET_OPT_IN=$(echo "$RESUME_RESPONSE" | grep -o '"market_opt_in":[^,}]*' | tr -d ' "')
USERNAME=$(echo "$RESUME_RESPONSE" | grep -o '"username":"[^"]*"' | cut -d'"' -f4)
AUTO_SIGN_IN_EXPIRED=$(echo "$RESUME_RESPONSE" | grep -o '"is_auto_sign_in_expired":[^,}]*' | tr -d ' "')

echo "Session Flags:"
echo "  ACCESS_MODE: $ACCESS_MODE"
echo "  MARKET_OPT_IN: $MARKET_OPT_IN"
echo "  USERNAME: $USERNAME"
echo "  AUTO_SIGN_IN_EXPIRED: $AUTO_SIGN_IN_EXPIRED"

echo "Step 6: Executing the final GET login request to establish the internet connection..."
LOGIN_URL="${BASE_PORTAL_URL}/cp/login?_=${TIMESTAMP}&access_mode=${ACCESS_MODE}&market_opt_in=${MARKET_OPT_IN}&username=${USERNAME}&auto_sign_in_expired=${AUTO_SIGN_IN_EXPIRED}&resume=true&command=login&lang=en&sn=${SN}&ssid=${SSID}&ip=${IP}&client_mac=${CLIENT_MAC}&host_ip=${HOST_IP}&host_mac=${HOST_MAC}&name=&time=${TIME}&cp_id=${CP_ID}&checksum=${CHECKSUM}&orig_url=${ORIG_URL}&browser=generic"

FINAL_LOGIN_RESPONSE=$(curl -v -L -c /tmp/cookies.txt -b /tmp/cookies.txt -A "$USER_AGENT" "$LOGIN_URL")
echo "Final Login Response: $FINAL_LOGIN_RESPONSE"

echo "Step 7: Verifying internet connectivity..."
if ping -c 3 8.8.8.8 >/dev/null; then
    echo "SUCCESS: Connected to the internet!"
    exit 0
else
    echo "ERROR: Connectivity check failed."
    exit 1
fi