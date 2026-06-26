#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
echo "Starting multi-stage login for RRX_Hotspot_portal_iob" | tee -a "$LOG_FILE"

echo "Waiting for DHCP..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then echo "Gateway found." | tee -a "$LOG_FILE"; sleep 6; break; fi
    sleep 1
done

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Stage 1: Capturing redirect data..." | tee -a "$LOG_FILE"
# Get the full redirect URL containing the Hotsplots challenge parameters
FULL_REDIRECT=$(curl -v -A "$USER_AGENT" -L -c /tmp/cookies.txt http://detectportal.firefox.com/success.txt 2>&1 | grep -o 'Location: http://portal.iob.de?loginurl=[^ ]*' | cut -d' ' -f2)
LOGIN_URL_ENCODED=$(echo "$FULL_REDIRECT" | grep -oP 'loginurl=\K.*')

if [ -z "$LOGIN_URL_ENCODED" ]; then
    echo "Error: Could not find loginurl in redirect." | tee -a "$LOG_FILE"
    exit 1
fi

# Decode the URL
DECODED_LOGIN_URL=$(echo -e "${LOGIN_URL_ENCODED//%/\\x}")
echo "Decoded Login URL: $DECODED_LOGIN_URL" | tee -a "$LOG_FILE"

echo "Stage 2: Hitting prelogin to initialize session..." | tee -a "$LOG_FILE"
curl -v -A "$USER_AGENT" -b /tmp/cookies.txt -c /tmp/cookies.txt -L "http://192.168.44.1/prelogin" > /dev/null 2>&1

echo "Stage 3: Submitting Hotsplots Auth..." | tee -a "$LOG_FILE"
# The portal requires the 'button' and 'accept' fields as seen in standard Hotsplots auth flow
RESPONSE=$(curl -v -A "$USER_AGENT" -b /tmp/cookies.txt -c /tmp/cookies.txt -X POST "$DECODED_LOGIN_URL" -d "button=Login&accept=Accept" 2>&1)
echo "HTTP Response from auth: $RESPONSE" | tee -a "$LOG_FILE"

sleep 5
echo "Verifying internet connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Successfully logged in!" | tee -a "$LOG_FILE" || { echo "Login failed." | tee -a "$LOG_FILE"; exit 1; }