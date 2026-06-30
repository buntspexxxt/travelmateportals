#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
echo "Starting Hotsplots login process..." | tee -a "$LOG_FILE"

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
TEMP_HTML=$(mktemp)

echo "Fetching initial redirect to extract session parameters..." | tee -a "$LOG_FILE"
# We target the actual login page to get the initial state
curl -v -A "$USER_AGENT" -c /tmp/cookies.txt -L "http://www.hotsplots.de/auth/login.php" -o "$TEMP_HTML"

# Extracting hidden fields dynamically
CHALLENGE=$(grep -o 'name="challenge" value="[^"]*"' "$TEMP_HTML" | cut -d'"' -f4)
UAMIP=$(grep -o 'name="uamip" value="[^"]*"' "$TEMP_HTML" | cut -d'"' -f4)
UAMPORT=$(grep -o 'name="uamport" value="[^"]*"' "$TEMP_HTML" | cut -d'"' -f4)
USERURL=$(grep -o 'name="userurl" value="[^"]*"' "$TEMP_HTML" | cut -d'"' -f4)
NASID=$(grep -o 'name="nasid" value="[^"]*"' "$TEMP_HTML" | cut -d'"' -f4)

echo "Extracted Challenge: $CHALLENGE" | tee -a "$LOG_FILE"

echo "Submitting acceptance POST request..." | tee -a "$LOG_FILE"
# The portal requires haveTerms=1, termsOK=on, and the hidden challenge/nasid fields
# We follow the form action exactly
RESPONSE=$(curl -v -A "$USER_AGENT" -b /tmp/cookies.txt -c /tmp/cookies.txt \
  -d "haveTerms=1&termsOK=on&challenge=$CHALLENGE&uamip=$UAMIP&uamport=$UAMPORT&userurl=$USERURL&myLogin=agb&ll=de&nasid=$NASID&custom=1&button=kostenlos+einloggen" \
  "https://www.hotsplots.de/auth/login.php" 2>&1)

echo "HTTP Response captured. Checking connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Success: Internet access verified." | tee -a "$LOG_FILE" && exit 0 || echo "Failure: Internet access check failed." | tee -a "$LOG_FILE" && exit 1