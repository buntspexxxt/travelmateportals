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
REDIRECT_RESPONSE=$(curl -v -L -A "$USER_AGENT" -o /dev/null -w "%{url_effective}" http://detectportal.firefox.com/success.txt 2>&1)

# Extract the Hotsplots login URL which contains the necessary challenge strings
LOGIN_URL=$(echo "$REDIRECT_RESPONSE" | grep -oP 'http[s]?://www.hotsplots.de/auth/login.php[^ ]*')

if [ -z "$LOGIN_URL" ]; then
    echo "Error: Could not extract Hotsplots login URL." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Stage 2: Accessing prelogin page..." | tee -a "$LOG_FILE"
# Based on the HTML, we must trigger the prelogin step to reach the Hotsplots portal
curl -v -A "$USER_AGENT" -L "http://192.168.44.1/prelogin" > /dev/null 2>&1

echo "Stage 3: Submitting final login to Hotsplots..." | tee -a "$LOG_FILE"
# Submitting the required accept parameter to the extracted Hotsplots URL
FINAL_RESPONSE=$(curl -v -A "$USER_AGENT" -X POST "$LOGIN_URL" -d "accept=Accept&button=Login" 2>&1)
echo "HTTP Response Received: $FINAL_RESPONSE" | tee -a "$LOG_FILE"

sleep 5
echo "Verifying internet connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Successfully logged in!" | tee -a "$LOG_FILE" || { echo "Login failed or no internet access." | tee -a "$LOG_FILE"; exit 1; }