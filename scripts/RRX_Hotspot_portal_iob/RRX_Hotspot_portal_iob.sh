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

echo "Stage 1: Capturing dynamic redirect parameters..." | tee -a "$LOG_FILE"
# Capture the initial redirect containing the hotsplots login URL and parameters
RESPONSE_HEADER=$(curl -v -A "$USER_AGENT" -L http://detectportal.firefox.com/success.txt 2>&1)
LOGIN_URL=$(echo "$RESPONSE_HEADER" | grep -oP 'Location: \Khttps?://[^ ]*/auth/login.php\?res=notyet[^ ]*' | head -n 1 | sed 's/\r//g')

if [ -z "$LOGIN_URL" ]; then
    echo "Error: Could not extract Hotsplots login URL." | tee -a "$LOG_FILE"
    exit 1
fi
echo "Login URL found: $LOGIN_URL" | tee -a "$LOG_FILE"

echo "Stage 2: Accessing prelogin portal landing..." | tee -a "$LOG_FILE"
# Hit the local landing page as indicated by the RRX index.html to trigger session initiation
curl -v -A "$USER_AGENT" -c /tmp/cookies.txt -b /tmp/cookies.txt -L "http://192.168.44.1/prelogin" > /dev/null 2>&1

echo "Stage 3: Submitting authentication to Hotsplots..." | tee -a "$LOG_FILE"
# The Hotsplots auth endpoint requires specific query params (challenge, etc) and POST data
# We use the extracted LOGIN_URL which already contains the necessary parameters
FINAL_RESPONSE=$(curl -v -A "$USER_AGENT" -c /tmp/cookies.txt -b /tmp/cookies.txt -L -X POST "$LOGIN_URL" -d "button=Login&accept=Accept" 2>&1)

echo "HTTP Response Received: $FINAL_RESPONSE" | tee -a "$LOG_FILE"

sleep 5
echo "Verifying internet connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Successfully logged in!" | tee -a "$LOG_FILE" || { echo "Login failed or no internet access." | tee -a "$LOG_FILE"; exit 1; }