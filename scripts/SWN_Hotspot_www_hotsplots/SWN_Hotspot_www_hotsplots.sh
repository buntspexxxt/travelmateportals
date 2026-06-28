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

echo "Fetching initial portal redirect..." | tee -a "$LOG_FILE"
# Get initial redirect and save to file to extract parameters
curl -v -A "$USER_AGENT" -L http://detectportal.firefox.com/success.txt -o /tmp/portal.html > /tmp/curl_log.txt 2>&1

# Extract the URL from the curl log (the last Location header)
REDIRECT_URL=$(grep -i "Location:" /tmp/curl_log.txt | tail -n 1 | sed -n 's/.*Location: //p' | tr -d '\r')
echo "Captured Redirect URL: $REDIRECT_URL" | tee -a "$LOG_FILE"

# Extract query parameters dynamically
CHALLENGE=$(echo "$REDIRECT_URL" | grep -oP 'challenge=\K[^&]+')
UAMIP=$(echo "$REDIRECT_URL" | grep -oP 'uamip=\K[^&]+')
UAMPORT=$(echo "$REDIRECT_URL" | grep -oP 'uamport=\K[^&]+')
USERURL=$(echo "$REDIRECT_URL" | grep -oP 'userurl=\K[^&]+')
NASID=$(echo "$REDIRECT_URL" | grep -oP 'nasid=\K[^&]+')

echo "Extracted Challenge: $CHALLENGE" | tee -a "$LOG_FILE"

echo "Submitting form to complete login..." | tee -a "$LOG_FILE"
RESPONSE=$(curl -v -A "$USER_AGENT" -X POST "https://www.hotsplots.de/auth/login.php" \
    -d "haveTerms=1" \
    -d "termsOK=1" \
    -d "challenge=$CHALLENGE" \
    -d "uamip=$UAMIP" \
    -d "uamport=$UAMPORT" \
    -d "userurl=$USERURL" \
    -d "myLogin=agb" \
    -d "nasid=$NASID" \
    -d "button=kostenlos+einloggen" 2>&1)

echo "HTTP Response Summary: $RESPONSE" | tee -a "$LOG_FILE"

echo "Checking connectivity..." | tee -a "$LOG_FILE"
ping -c 3 8.8.8.8 >> "$LOG_FILE" 2>&1 && echo "Successfully logged in!" && exit 0 || exit 1