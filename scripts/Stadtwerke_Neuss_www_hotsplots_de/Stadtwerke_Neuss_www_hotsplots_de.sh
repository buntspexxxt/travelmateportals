#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
echo "Starting login script..." | tee -a "$LOG_FILE"

# 1. Wait for DHCP
echo "Waiting for DHCP (IP & Gateway)..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then
        echo "Gateway found! DHCP successful." | tee -a "$LOG_FILE"
        sleep 6
        break
    fi
    sleep 1
done

# 2. Fetch redirect URL to get dynamic parameters
echo "Fetching initial portal redirect..." | tee -a "$LOG_FILE"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
RESPONSE_HEADERS=$(curl -v -A "$USER_AGENT" -L -o /tmp/portal.html http://neverssl.com 2>&1)

# 3. Extract redirect URL
REDIRECT_URL=$(echo "$RESPONSE_HEADERS" | sed -n 's/.*Location: //p' | tr -d '\r' | tail -n 1)
echo "Captured Redirect URL: $REDIRECT_URL" | tee -a "$LOG_FILE"

# 4. Extract dynamic POST parameters from the HTML/URL
# Extracting query string for form submission
QUERY_STRING=$(echo "$REDIRECT_URL" | sed -n 's/.*\?\(.*\)/\1/p')
CHALLENGE=$(echo "$REDIRECT_URL" | sed -n 's/.*challenge=\([^&]*\).*/\1/p')
UAMIP=$(echo "$REDIRECT_URL" | sed -n 's/.*uamip=\([^&]*\).*/\1/p')
UAMPORT=$(echo "$REDIRECT_URL" | sed -n 's/.*uamport=\([^&]*\).*/\1/p')
NASID=$(echo "$REDIRECT_URL" | sed -n 's/.*nasid=\([^&]*\).*/\1/p')

echo "Extracted Challenge: $CHALLENGE" | tee -a "$LOG_FILE"

# 5. Perform Login
echo "Submitting login form..." | tee -a "$LOG_FILE"
# We use the same parameters as seen in the HTML input fields
POST_DATA="haveTerms=1&termsOK=on&challenge=$CHALLENGE&uamip=$UAMIP&uamport=$UAMPORT&nasid=$NASID&myLogin=agb&custom=1&button=kostenlos+einloggen"

curl -v -A "$USER_AGENT" -d "$POST_DATA" -c /tmp/cookies.txt -b /tmp/cookies.txt https://www.hotsplots.de/auth/login.php | tee -a "$LOG_FILE"

# 6. Connectivity Check
echo "Checking internet connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Successfully logged in and online." | tee -a "$LOG_FILE" || { echo "Login failed or no internet." | tee -a "$LOG_FILE"; exit 1; }