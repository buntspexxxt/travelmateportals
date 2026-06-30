#!/bin/bash
LOG_FILE="/tmp/portal_login.log"
echo "Starting login process" | tee -a "$LOG_FILE"
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

echo "Fetching portal landing page to extract hidden fields..." | tee -a "$LOG_FILE"
curl -v -A "$USER_AGENT" -c /tmp/cookies.txt "http://detectportal.firefox.com/success.txt" -o "$TEMP_HTML"

# Extract hidden fields
CHALLENGE=$(grep -o 'name="challenge" value="[^"]*"' "$TEMP_HTML" | cut -d'"' -f4)
UAMIP=$(grep -o 'name="uamip" value="[^"]*"' "$TEMP_HTML" | cut -d'"' -f4)
UAMPORT=$(grep -o 'name="uamport" value="[^"]*"' "$TEMP_HTML" | cut -d'"' -f4)
USERURL=$(grep -o 'name="userurl" value="[^"]*"' "$TEMP_HTML" | cut -d'"' -f4)
NASID=$(grep -o 'name="nasid" value="[^"]*"' "$TEMP_HTML" | cut -d'"' -f4)

echo "Extracted Challenge: $CHALLENGE" | tee -a "$LOG_FILE"
echo "Submitting login form..." | tee -a "$LOG_FILE"

RESPONSE=$(curl -v -A "$USER_AGENT" -b /tmp/cookies.txt -c /tmp/cookies.txt \
  --data "haveTerms=1&termsOK=on&challenge=$CHALLENGE&uamip=$UAMIP&uamport=$UAMPORT&userurl=$USERURL&nasid=$NASID&myLogin=agb&ll=de&custom=1&button=kostenlos+einloggen" \
  "https://www.hotsplots.de/auth/login.php")

echo "Login submission completed." | tee -a "$LOG_FILE"

echo "Checking connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Success: Internet access verified." | tee -a "$LOG_FILE" && exit 0 || echo "Failure: Internet access check failed." | tee -a "$LOG_FILE" && exit 1