#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
echo "Starting multi-stage login for RRX_Hotspot_portal_iob" | tee -a "$LOG_FILE"

echo "Waiting for DHCP..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then echo "Gateway found." | tee -a "$LOG_FILE"; sleep 6; break; fi
    sleep 1
done

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Stage 1: Extracting Hotsplots redirect URL..." | tee -a "$LOG_FILE"
# Capture initial redirect to identify the Hotsplots auth URL in the query string
REDIRECT_URL=$(curl -v -A "$USER_AGENT" -L http://detectportal.firefox.com/success.txt 2>&1 | grep -oP 'loginurl=\Khttps?%3a%2f%2fwww.hotsplots.de%2fauth%2flogin.php%3fres%3dnotyet%26.*' | sed 's/%3a/:/g; s/%2f/\//g; s/%3f/?/g; s/%26/\&/g; s/%3d/=/g' | cut -d' ' -f1)

if [ -z "$REDIRECT_URL" ]; then
    echo "Error: Could not extract Hotsplots login URL." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Stage 2: Accessing prelogin portal..." | tee -a "$LOG_FILE"
# Access the landing page required by the RRX index.html to establish session state
curl -v -A "$USER_AGENT" -c /tmp/cookies.txt -L "http://192.168.44.1/prelogin" > /dev/null 2>&1

echo "Stage 3: Submitting authentication to Hotsplots..." | tee -a "$LOG_FILE"
# Hotsplots login submission - sending button=Login and accept=Accept as required
RESPONSE=$(curl -v -A "$USER_AGENT" -c /tmp/cookies.txt -b /tmp/cookies.txt -L -X POST "$REDIRECT_URL" -d "button=Login&accept=Accept" 2>&1)

echo "Response received: $RESPONSE" | tee -a "$LOG_FILE"

sleep 5
echo "Verifying internet connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Successfully logged in!" | tee -a "$LOG_FILE" || { echo "Login failed." | tee -a "$LOG_FILE"; exit 1; }