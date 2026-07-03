#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
COOKIE_FILE="/tmp/hotsplots_cookies.txt"

echo "Waiting for DHCP..." | tee -a "$LOG_FILE"
for i in {1..20}; do
    if ip route | grep -q default; then echo "Gateway found." | tee -a "$LOG_FILE"; break; fi
    sleep 1
done

echo "Fetching portal redirection..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -v -A "$USER_AGENT" -c "$COOKIE_FILE" "http://neverssl.com" 2>&1)
LOCATION=$(echo "$RESPONSE" | sed -n 's/.*Location: \(.*\)/\1/p' | tr -d '\r')

if [ -z "$LOCATION" ]; then echo "Already online." | tee -a "$LOG_FILE"; exit 0; fi

echo "Accessing portal: $LOCATION" | tee -a "$LOG_FILE"
HTML=$(curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$LOCATION")

echo "Extracting hidden form parameters..." | tee -a "$LOG_FILE"
CHALLENGE=$(echo "$HTML" | sed -n 's/.*name="challenge" value="\([^"]*\)".*/\1/p')
UAMIP=$(echo "$HTML" | sed -n 's/.*name="uamip" value="\([^"]*\)".*/\1/p')
UAMPORT=$(echo "$HTML" | sed -n 's/.*name="uamport" value="\([^"]*\)".*/\1/p')
USERURL=$(echo "$HTML" | sed -n 's/.*name="userurl" value="\([^"]*\)".*/\1/p')
NASID=$(echo "$HTML" | sed -n 's/.*name="nasid" value="\([^"]*\)".*/\1/p')

if [ -z "$CHALLENGE" ]; then echo "Failed to extract parameters." | tee -a "$LOG_FILE"; exit 1; fi

echo "Submitting terms acceptance via POST..." | tee -a "$LOG_FILE"
# The form specifically checks for 'termsOK=on' and 'haveTerms=1'
POST_DATA="haveTerms=1&termsOK=on&button=kostenlos+einloggen&challenge=$CHALLENGE&uamip=$UAMIP&uamport=$UAMPORT&userurl=$USERURL&myLogin=agb&ll=de&nasid=$NASID&custom=1"

AUTH_RESPONSE=$(curl -v -A "$USER_AGENT" -b "$COOKIE_FILE" -d "$POST_DATA" "https://www.hotsplots.de/auth/login.php" 2>&1)
echo "HTTP Response: $AUTH_RESPONSE" | tee -a "$LOG_FILE"

sleep 2
echo "Verifying internet connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && (echo "Login successful!" | tee -a "$LOG_FILE" && exit 0) || (echo "Login failed." | tee -a "$LOG_FILE" && exit 1)