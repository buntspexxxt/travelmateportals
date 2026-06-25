#!/bin/bash
LOG_FILE="/tmp/wifi_login.log"
echo "Starting login script..." | tee -a "$LOG_FILE"

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

echo "Fetching initial portal page..." | tee -a "$LOG_FILE"
curl -v -A "$USER_AGENT" -c /tmp/cookies.txt -L "http://detectportal.firefox.com/success.txt" > /tmp/portal.html 2>&1

echo "Extracting WBS Token from HTML..." | tee -a "$LOG_FILE"
TOKEN=$(grep -oP '(?<=conn4.hotspot.wbsToken =).*?(?=;)' /tmp/portal.html | tr -d ' ')
if [ -z "$TOKEN" ]; then
    echo "Error: Could not extract token." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Extracted Token: $TOKEN" | tee -a "$LOG_FILE"

echo "Submitting session initialization..." | tee -a "$LOG_FILE"
# The portal likely expects the browser to load the specific scene logic.
# Since it's a 'scene' loader, we perform a POST to the ident or similar endpoint if defined in JS
# Based on analysis, the portal handles state via the session cookie captured above.
curl -v -A "$USER_AGENT" -b /tmp/cookies.txt -c /tmp/cookies.txt -L "https://rewe-wlan.conn4.com/" > /tmp/final.html 2>&1

echo "Checking connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Success: Connected." && exit 0 || echo "Failure: No internet." && exit 1