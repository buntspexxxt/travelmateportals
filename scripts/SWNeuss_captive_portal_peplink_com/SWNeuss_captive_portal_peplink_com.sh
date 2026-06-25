#!/bin/env bash

LOG_FILE="/tmp/portal_debug.log"
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

echo "Step 1: Fetching initial redirect to capture portal context..." | tee -a "$LOG_FILE"
REDIRECT_URL=$(curl -v -L -o /dev/null -w "%{url_effective}" -A "$USER_AGENT" "http://detectportal.firefox.com/success.txt" 2>&1 | grep "Location:" | tail -n1 | awk '{print $2}')

echo "Extracted URL: $REDIRECT_URL" | tee -a "$LOG_FILE"

# Extracting parameters
SN=$(echo "$REDIRECT_URL" | grep -o 'sn=[^&]*' | cut -d= -f2)
SSID=$(echo "$REDIRECT_URL" | grep -o 'ssid=[^&]*' | cut -d= -f2)
IP=$(echo "$REDIRECT_URL" | grep -o 'ip=[^&]*' | cut -d= -f2)
CLIENT_MAC=$(echo "$REDIRECT_URL" | grep -o 'client_mac=[^&]*' | cut -d= -f2)
HOST_IP=$(echo "$REDIRECT_URL" | grep -o 'host_ip=[^&]*' | cut -d= -f2)
HOST_MAC=$(echo "$REDIRECT_URL" | grep -o 'host_mac=[^&]*' | cut -d= -f2)
TIME=$(echo "$REDIRECT_URL" | grep -o 'time=[^&]*' | cut -d= -f2)
CP_ID=$(echo "$REDIRECT_URL" | grep -o 'cp_id=[^&]*' | cut -d= -f2)
CHECKSUM=$(echo "$REDIRECT_URL" | grep -o 'checksum=[^&]*' | cut -d= -f2)

echo "Step 2: Resuming session..." | tee -a "$LOG_FILE"
TS=$(date +%s)000
RESUME_URL="https://guest7.ic.peplink.com/cp/session/resume?client_mac=${CLIENT_MAC}&sn=${SN}&ssid=${SSID}&time=${TIME}&cp_id=${CP_ID}&checksum=${CHECKSUM}&_=${TS}"

RESPONSE=$(curl -v -c /tmp/cookies.txt -b /tmp/cookies.txt -A "$USER_AGENT" "$RESUME_URL")
echo "Resume Response: $RESPONSE" | tee -a "$LOG_FILE"

# If session resume returns is_prompt_sign_in, we must trigger the login flow
echo "Step 3: Proceeding to Login..." | tee -a "$LOG_FILE"
LOGIN_URL="https://guest7.ic.peplink.com/cp/login?_= ${TS}&access_mode=1&resume=true&command=login&sn=${SN}&ssid=${SSID}&ip=${IP}&client_mac=${CLIENT_MAC}&host_ip=${HOST_IP}&host_mac=${HOST_MAC}&time=${TIME}&cp_id=${CP_ID}&checksum=${CHECKSUM}&orig_url=http://detectportal.firefox.com/success.txt"

curl -v -L -c /tmp/cookies.txt -b /tmp/cookies.txt -A "$USER_AGENT" "$LOGIN_URL"

echo "Step 4: Connectivity check..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Success: Internet active." || { echo "Error: Connection failed." && exit 1; }