#!/bin/env bash

# Helper function to decode URL-encoded parameters
urldecode() {
    echo "$1" | sed 's/%3A/:/g; s/%2F/\//g; s/%3F/?/g; s/%3D/=/g; s/%26/\&/g; s/%2C/,/g; s/%2B/+/g; s/%20/ /g; s/%40/@/g'
}

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Step 1: Fetching initial redirect to capture portal context..."
REDIRECT_URL=$(curl -v -L -o /dev/null -w "%{url_effective}" -A "$USER_AGENT" "http://detectportal.firefox.com/success.txt")

echo "Extracted URL: $REDIRECT_URL"

# Extract parameters dynamically using regex extraction from URL
CHECKSUM=$(echo "$REDIRECT_URL" | grep -o 'checksum=[^&]*' | cut -d= -f2)
CP_ID=$(echo "$REDIRECT_URL" | grep -o 'cp_id=[^&]*' | cut -d= -f2)
TIME=$(echo "$REDIRECT_URL" | grep -o 'time=[^&]*' | cut -d= -f2)
IP=$(echo "$REDIRECT_URL" | grep -o 'ip=[^&]*' | cut -d= -f2)
CLIENT_MAC=$(echo "$REDIRECT_URL" | grep -o 'client_mac=[^&]*' | cut -d= -f2)
SN=$(echo "$REDIRECT_URL" | grep -o 'sn=[^&]*' | cut -d= -f2)
SSID=$(echo "$REDIRECT_URL" | grep -o 'ssid=[^&]*' | cut -d= -f2)
HOST_IP=$(echo "$REDIRECT_URL" | grep -o 'host_ip=[^&]*' | cut -d= -f2)
HOST_MAC=$(echo "$REDIRECT_URL" | grep -o 'host_mac=[^&]*' | cut -d= -f2)
ORIG_URL="http://detectportal.firefox.com/success.txt"

echo "Step 2: Checking session status..."
TIMESTAMP=$(date +%s)000
RESUME_URL="https://guest7.ic.peplink.com/cp/session/resume?client_mac=${CLIENT_MAC}&sn=${SN}&ssid=${SSID}&time=${TIME}&cp_id=${CP_ID}&checksum=${CHECKSUM}&_=${TIMESTAMP}"

RESUME_RESPONSE=$(curl -v -c /tmp/cookies.txt -b /tmp/cookies.txt -A "$USER_AGENT" "$RESUME_URL")
echo "Resume Status: $RESUME_RESPONSE"

# Extract flags
ACCESS_MODE=$(echo "$RESUME_RESPONSE" | grep -o '"access_mode":"[^"]*"' | cut -d'"' -f4)
MARKET_OPT_IN=$(echo "$RESUME_RESPONSE" | grep -o '"market_opt_in":[^,}]*' | tr -d ' "')
USERNAME=$(echo "$RESUME_RESPONSE" | grep -o '"username":"[^"]*"' | cut -d'"' -f4)
AUTO_SIGN_IN_EXPIRED=$(echo "$RESUME_RESPONSE" | grep -o '"is_auto_sign_in_expired":[^,}]*' | tr -d ' "')

echo "Step 3: Submitting login credentials to finalize portal entry..."
LOGIN_URL="https://guest7.ic.peplink.com/cp/login?_=${TIMESTAMP}&access_mode=${ACCESS_MODE}&market_opt_in=${MARKET_OPT_IN}&username=${USERNAME}&auto_sign_in_expired=${AUTO_SIGN_IN_EXPIRED}&resume=true&command=login&lang=en&sn=${SN}&ssid=${SSID}&ip=${IP}&client_mac=${CLIENT_MAC}&host_ip=${HOST_IP}&host_mac=${HOST_MAC}&time=${TIME}&cp_id=${CP_ID}&checksum=${CHECKSUM}&orig_url=${ORIG_URL}&browser=generic"

LOGIN_RESULT=$(curl -v -L -c /tmp/cookies.txt -b /tmp/cookies.txt -A "$USER_AGENT" "$LOGIN_URL")
echo "Login Result Captured."

echo "Step 4: Connectivity check..."
ping -c 3 8.8.8.8 >/dev/null && echo "Success: Internet active." || { echo "Error: Connection failed."; exit 1; }