#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
echo "Starting multi-stage login process for RRX_Hotspot_portal_iob" | tee -a "$LOG_FILE"

echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Stage 1: Fetching initial redirect parameters..." | tee -a "$LOG_FILE"
REDIRECT_RAW=$(curl -v -L -A "$USER_AGENT" -o /dev/null -w "%{url_effective}" http://detectportal.firefox.com/success.txt 2>&1)

LOGIN_URL=$(echo "$REDIRECT_RAW" | grep -oP 'loginurl=\K[^ ]+' | sed 's/&/\&/g' | python3 -c "import sys, urllib.parse; print(urllib.parse.unquote(sys.stdin.read().strip()))")

if [ -z "$LOGIN_URL" ]; then
    echo "Error: Could not extract Hotsplots login URL." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Stage 2: Accessing pre-login endpoint to establish session..." | tee -a "$LOG_FILE"
curl -v -A "$USER_AGENT" -c /tmp/cookies.txt -b /tmp/cookies.txt -L "http://192.168.44.1/prelogin" > /dev/null 2>&1

echo "Stage 3: Submitting authentication to Hotsplots..." | tee -a "$LOG_FILE"
# The portal requires a standard hotsplots login, we pass the extracted parameters dynamically
FINAL_RESPONSE=$(curl -v -A "$USER_AGENT" -c /tmp/cookies.txt -b /tmp/cookies.txt -L -X POST "$LOGIN_URL" -d "accept=Accept&button=Login" 2>&1)

echo "HTTP Response Received: $FINAL_RESPONSE" | tee -a "$LOG_FILE"

sleep 5
echo "Verifying internet connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Successfully logged in!" | tee -a "$LOG_FILE" || { echo "Login failed or no internet access." | tee -a "$LOG_FILE"; exit 1; }