#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
echo "Starting multi-stage login script..." | tee -a "$LOG_FILE"

echo "Waiting for DHCP..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then echo "Gateway found." | tee -a "$LOG_FILE"; sleep 6; break; fi
    sleep 1
done

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE="/tmp/cookies.txt"
BASE_URL="https://service.thecloud.eu/service-platform"

echo "Stage 1: Initializing session..." | tee -a "$LOG_FILE"
curl -v -A "$USER_AGENT" -c "$COOKIE_FILE" "$BASE_URL/" > /tmp/init.html 2>&1

echo "Stage 2: Extracting 'Get Online' URL..." | tee -a "$LOG_FILE"
GET_ONLINE_URL=$(grep -o 'https://service.thecloud.eu/service-platform/url/[0-9]*' /tmp/init.html | head -1)

if [ -z "$GET_ONLINE_URL" ]; then echo "Failed to find Get Online URL." | tee -a "$LOG_FILE"; exit 1; fi

echo "Navigating to: $GET_ONLINE_URL" | tee -a "$LOG_FILE"
REDIRECT_RESPONSE=$(curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -L -o /tmp/landing.html "$GET_ONLINE_URL" 2>&1)

echo "Stage 3: Looking for secondary confirmation..." | tee -a "$LOG_FILE"
# The portal often requires a drift_time call or specific tracking before session is active
DRIFT_URL=$(grep -o '"drift_time_[0-9]*"' /tmp/landing.html | head -1 | tr -d '"')
if [ ! -z "$DRIFT_URL" ]; then
    echo "Performing drift_time request..." | tee -a "$LOG_FILE"
    curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" "$BASE_URL/$DRIFT_URL" > /dev/null 2>&1
fi

echo "Connectivity check..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Connected!" && exit 0 || exit 1