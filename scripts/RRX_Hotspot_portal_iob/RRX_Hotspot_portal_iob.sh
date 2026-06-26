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
# Using -I to just get headers, capturing the Location header where the loginurl is stored
REDIRECT_RAW=$(curl -v -A "$USER_AGENT" -I http://detectportal.firefox.com/success.txt 2>&1 | grep -i "Location:" | head -n 1)
echo "Redirect location found: $REDIRECT_RAW" | tee -a "$LOG_FILE"

# Extracting the login URL from the Location header
LOGIN_URL=$(echo "$REDIRECT_RAW" | grep -oP 'loginurl=\Khttps%3A%2F%2Fwww.hotsplots.de%2Fauth%2Flogin.php%3Fres%3dnotyet[^ ]*' | sed 's/&/\&/g' | python3 -c "import sys, urllib.parse; print(urllib.parse.unquote(sys.stdin.read().strip()))")

if [ -z "$LOGIN_URL" ]; then
    echo "Error: Could not extract Hotsplots login URL from redirect." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Extracted Login URL: $LOGIN_URL" | tee -a "$LOG_FILE"

echo "Stage 2: Accessing pre-login endpoint..." | tee -a "$LOG_FILE"
# Accessing the portal provided link first as per landing page logic
curl -v -A "$USER_AGENT" -c /tmp/cookies.txt -b /tmp/cookies.txt -L "http://192.168.44.1/prelogin" > /dev/null 2>&1

echo "Stage 3: Submitting final authentication to Hotsplots..." | tee -a "$LOG_FILE"
# Following the Hotspots flow with the specific query params extracted
FINAL_RESPONSE=$(curl -v -A "$USER_AGENT" -c /tmp/cookies.txt -b /tmp/cookies.txt -L -X POST "$LOGIN_URL" -d "button=Login&accept=Accept" 2>&1)

echo "HTTP Response Received: $FINAL_RESPONSE" | tee -a "$LOG_FILE"

sleep 5
echo "Verifying internet connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Successfully logged in!" | tee -a "$LOG_FILE" || { echo "Login failed or no internet access." | tee -a "$LOG_FILE"; exit 1; }