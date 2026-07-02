#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "Starting login script for Stadtwerke_Neuss..." | tee -a "$LOG_FILE"

# 1. Wait for DHCP
echo "Waiting for DHCP..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then echo "Gateway found!" | tee -a "$LOG_FILE"; sleep 5; break; fi
    sleep 1
done

# 2. Get initial challenge and form hidden fields
echo "Fetching initial redirect parameters..." | tee -a "$LOG_FILE"
PAGE_CONTENT=$(curl -v -A "$USER_AGENT" -L -c /tmp/cookies.txt "http://neverssl.com" 2>&1)
REDIRECT_URL=$(echo "$PAGE_CONTENT" | sed -n "s/.*Location: //p" | tr -d '\\r' | tail -n 1)

# Extracting parameters from URL
CHALLENGE=$(echo "$REDIRECT_URL" | sed -n 's/.*challenge=\([^&]*\).*/\1/p')
UAMIP=$(echo "$REDIRECT_URL" | sed -n 's/.*uamip=\([^&]*\).*/\1/p')
UAMPORT=$(echo "$REDIRECT_URL" | sed -n 's/.*uamport=\([^&]*\).*/\1/p')
NASID=$(echo "$REDIRECT_URL" | sed -n 's/.*nasid=\([^&]*\).*/\1/p')

echo "Challenge: $CHALLENGE" | tee -a "$LOG_FILE"

# 3. Submit Terms and Login
echo "Submitting form to accept Terms of Service..." | tee -a "$LOG_FILE"
# We use the parameters identified in the HTML form
POST_DATA="haveTerms=1&termsOK=on&challenge=$CHALLENGE&uamip=$UAMIP&uamport=$UAMPORT&nasid=$NASID&myLogin=agb&custom=1&button=kostenlos+einloggen"

RESPONSE=$(curl -v -A "$USER_AGENT" -d "$POST_DATA" -b /tmp/cookies.txt -c /tmp/cookies.txt "https://www.hotsplots.de/auth/login.php" 2>&1)
echo "HTTP Response Check completed." | tee -a "$LOG_FILE"

# 4. Connectivity Check
echo "Verifying internet access..." | tee -a "$LOG_FILE"
sleep 5
ping -c 3 8.8.8.8 >/dev/null && { echo "Successfully logged in!" | tee -a "$LOG_FILE"; exit 0; } || { echo "Login failed. No internet connectivity." | tee -a "$LOG_FILE"; exit 1; }