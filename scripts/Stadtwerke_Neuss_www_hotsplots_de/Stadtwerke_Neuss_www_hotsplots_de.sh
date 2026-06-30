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

echo "Fetching portal landing page to extract parameters..." | tee -a "$LOG_FILE"
# Using curl to capture initial redirect headers to get the query parameters
REDIRECT_URL=$(curl -v -A "$USER_AGENT" -c /tmp/cookies.txt -L "http://detectportal.firefox.com/success.txt" 2>&1 | grep -oE "Location: https://www.hotsplots.de/auth/login.php[^]+" | sed -n "s/.*Location: //p" | tr -d '\r')

if [ -z "$REDIRECT_URL" ]; then
    echo "Failed to extract redirect URL. Exiting." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Fetching login form from: $REDIRECT_URL" | tee -a "$LOG_FILE"
curl -v -A "$USER_AGENT" -b /tmp/cookies.txt -c /tmp/cookies.txt "$REDIRECT_URL" -o "$TEMP_HTML"

# Extract hidden fields dynamically
CHALLENGE=$(grep -o 'name="challenge" value="[^"]*"' "$TEMP_HTML" | cut -d'"' -f4)
UAMIP=$(grep -o 'name="uamip" value="[^"]*"' "$TEMP_HTML" | cut -d'"' -f4)
UAMPORT=$(grep -o 'name="uamport" value="[^"]*"' "$TEMP_HTML" | cut -d'"' -f4)
USERURL=$(grep -o 'name="userurl" value="[^"]*"' "$TEMP_HTML" | cut -d'"' -f4)
NASID=$(grep -o 'name="nasid" value="[^"]*"' "$TEMP_HTML" | cut -d'"' -f4)

echo "Submitting form with parameters: Challenge=$CHALLENGE, NASID=$NASID" | tee -a "$LOG_FILE"

# Submit the form. 'termsOK=on' is required by the checkbox
RESPONSE=$(curl -v -A "$USER_AGENT" -b /tmp/cookies.txt -c /tmp/cookies.txt \
  --data-urlencode "haveTerms=1" \
  --data-urlencode "termsOK=on" \
  --data-urlencode "challenge=$CHALLENGE" \
  --data-urlencode "uamip=$UAMIP" \
  --data-urlencode "uamport=$UAMPORT" \
  --data-urlencode "userurl=$USERURL" \
  --data-urlencode "nasid=$NASID" \
  --data-urlencode "myLogin=agb" \
  --data-urlencode "ll=de" \
  --data-urlencode "custom=1" \
  --data-urlencode "button=kostenlos einloggen" \
  "https://www.hotsplots.de/auth/login.php")

echo "Login response received." | tee -a "$LOG_FILE"

echo "Checking final connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >/dev/null && echo "Success: Internet access verified." | tee -a "$LOG_FILE" && exit 0 || echo "Failure: Internet access check failed." | tee -a "$LOG_FILE" && exit 1